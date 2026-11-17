import {
  cloudAccess,
  cloudRateLimit,
  preAuthRateLimit,
} from './server/cloudAccess';
import { randomUUID } from 'node:crypto';
import express from 'express';
import { createServer as createViteServer } from 'vite';
import { WebSocketServer, WebSocket } from 'ws';
import { GoogleGenAI, Modality, Type } from '@google/genai';
import path from 'path';
import fs from 'fs';
import http from 'http';
import { fileURLToPath } from 'url';
import { redactSensitiveText, sanitizeContextForCloudAi } from './src/lib/privacyGate';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PORT = Number(process.env.PORT) || 3000;

function getGenAI() {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error('GEMINI_API_KEY is not configured in environment');
  }
  return new GoogleGenAI({
    apiKey,
    httpOptions: {
      headers: {
        'User-Agent': 'aistudio-build',
      },
    },
  });
}

// Primary and fallback models for text/chat/grounding
const PRIMARY_CHAT_MODEL = 'gemini-3.8-flash';
const FALLBACK_CHAT_MODEL = 'gemini-3.1-flash-lite';
const TRANSCRIBE_MODEL = 'gemini-3.5-transcribe';
const LIVE_VOICE_MODEL = 'gemini-3.8-live';

// Coordinated server-side deadlines (must finish before client's 26,000ms deadline)
const PRIMARY_DEADLINE_MS = 6500;
const FALLBACK_DEADLINE_MS = 14000;

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => {
      const err: any = new Error(`${label} timed out after ${timeoutMs}ms`);
      err.status = 504;
      err.code = 'DEADLINE_EXCEEDED';
      reject(err);
    }, timeoutMs);

    promise.then(
      (val) => {
        clearTimeout(timer);
        resolve(val);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      }
    );
  });
}

function shouldFallbackModel(err: any): boolean {
  const status = err?.status || err?.httpStatusCode || err?.code;
  const msg = String(err?.message || '').toLowerCase();
  return (
    status === 404 ||
    status === 429 ||
    status === 503 ||
    status === 504 ||
    status === 'DEADLINE_EXCEEDED' ||
    msg.includes('not found') ||
    msg.includes('not supported') ||
    msg.includes('high demand') ||
    msg.includes('unavailable') ||
    msg.includes('timed out') ||
    msg.includes('resource_exhausted')
  );
}

/**
 * Schema for structured chat + optional task breakdown output.
 * Supported by @google/genai on gemini-3.8-flash and gemini-3.1-flash-lite.
 */
const STRUCTURED_CHAT_SCHEMA = {
  type: Type.OBJECT,
  properties: {
    reply: {
      type: Type.STRING,
      description:
        'Warm, non-judgmental coaching reply to display in the chat message (plain text or markdown, max 3 short paragraphs).',
    },
    isTaskBreakdown: {
      type: Type.BOOLEAN,
      description:
        'Set to true ONLY when the user explicitly asks to break down, plan steps for, or get started on a specific task or chore. Set to false for greetings, general questions, or reflections.',
    },
    targetTaskTitle: {
      type: Type.STRING,
      description:
        'Concise title of the task being broken down when isTaskBreakdown is true; empty string otherwise.',
    },
    steps: {
      type: Type.ARRAY,
      description:
        '3 to 5 concrete, actionable micro-steps (2 to 15 minutes each) when isTaskBreakdown is true; empty array [] when isTaskBreakdown is false.',
      items: {
        type: Type.OBJECT,
        properties: {
          title: {
            type: Type.STRING,
            description: 'Concrete micro-step starting with an action verb (3 to 120 characters).',
          },
          estimatedMinutes: {
            type: Type.INTEGER,
            description: 'Estimated time in minutes (integer between 1 and 45).',
          },
          energy: {
            type: Type.STRING,
            description: 'Energy required: "low", "medium", or "high".',
          },
        },
        required: ['title', 'estimatedMinutes', 'energy'],
      },
    },
  },
  required: ['reply', 'isTaskBreakdown', 'steps'],
};

export interface ValidatedMicroStep {
  title: string;
  estimatedMinutes: number;
  energy: 'low' | 'medium' | 'high';
}

export interface ValidatedTaskBreakdown {
  targetTaskId?: string;
  targetTaskTitle: string;
  steps: ValidatedMicroStep[];
}

/**
 * Validates and normalizes structured output from the model.
 * Never fabricates steps on parser or validation failure.
 */
export function validateAndExtractChatOutput(
  rawText: string,
  _context?: Record<string, any>
): {
  reply: string;
  taskBreakdown: ValidatedTaskBreakdown | null;
} {
  const trimmed = (rawText || '').trim();
  if (!trimmed) {
    return {
      reply: "I'm here with you. Tell me what's on your mind or which task feels stuck.",
      taskBreakdown: null,
    };
  }

  try {
    const parsed = JSON.parse(trimmed);
    if (parsed && typeof parsed === 'object' && typeof parsed.reply === 'string') {
      const cleanReply = parsed.reply.trim();
      if (!parsed.isTaskBreakdown || !Array.isArray(parsed.steps) || parsed.steps.length === 0) {
        return {
          reply: cleanReply || "I'm here with you.",
          taskBreakdown: null,
        };
      }

      const validSteps: ValidatedMicroStep[] = [];
      for (const item of parsed.steps) {
        if (!item || typeof item !== 'object') continue;
        const rawTitle = typeof item.title === 'string' ? item.title : '';
        const cleanTitle = rawTitle
          .replace(/^(?:step\s*\d+[:.)-]?\s*|\d+[.)]\s*|[-*•]\s*)/i, '')
          .replace(/\*\*/g, '')
          .trim();

        if (cleanTitle.length < 3 || cleanTitle.length > 140) continue;

        const rawMins = Number(item.estimatedMinutes);
        const estimatedMinutes = Number.isFinite(rawMins)
          ? Math.max(1, Math.min(60, Math.round(rawMins)))
          : 5;

        const rawEnergy = String(item.energy || 'low').toLowerCase();
        const energy: 'low' | 'medium' | 'high' =
          rawEnergy === 'high' ? 'high' : rawEnergy === 'medium' ? 'medium' : 'low';

        validSteps.push({
          title: cleanTitle,
          estimatedMinutes,
          energy,
        });
      }

      return {
        reply: cleanReply || "I've drafted a starting sequence for you below.",
        taskBreakdown:
          validSteps.length > 0
            ? {
                targetTaskTitle: (parsed.targetTaskTitle || '').trim(),
                steps: validSteps,
              }
            : null,
      };
    }
  } catch {
    // If response was unstructured plain text markdown
  }

  return {
    reply: trimmed,
    taskBreakdown: null,
  };
}

const app = express();
const server = http.createServer(app);

// Pre-auth rate limiting protects public and unauthenticated requests
app.use('/api', preAuthRateLimit);
app.use(express.json({ limit: '25mb' }));

// Health Check (public, no authentication needed)
app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    version: '0.2.0-v2',
    timestamp: new Date().toISOString(),
  });
});

app.get('/api/gemini/health', (_req, res) => {
  res.json({
    status: 'ok',
    hasApiKey: Boolean(process.env.GEMINI_API_KEY),
  });
});

// Single-use ticket storage for Live Voice WebSocket sessions
const tickets = new Map<string, { uid: string; expires: number }>();
const activeVoiceUsers = new Set<string>();

app.post('/api/gemini/live-ticket', cloudAccess(), cloudRateLimit, (_req, res) => {
  for (const [key, value] of tickets) {
    if (value.expires < Date.now()) tickets.delete(key);
  }
  if (tickets.size >= 1000) {
    return res.status(503).json({ error: 'Voice is busy. Try again shortly.' });
  }
  const ticket = randomUUID();
  tickets.set(ticket, { uid: res.locals.uid, expires: Date.now() + 30_000 });
  res.json({ ticket });
});

// ---------------------------------------------------------------------------
// 1. Multi-Turn Lexi Chat & Task Breakdown Endpoint
// ---------------------------------------------------------------------------
app.post('/api/gemini/chat', cloudAccess(), cloudRateLimit, async (req, res) => {
  const startTime = Date.now();
  const requestId =
    (req.headers['x-request-id'] as string) ||
    req.body?.requestId ||
    `req-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;

  try {
    const { messages, context, enableSearch, model } = req.body || {};
    if (!Array.isArray(messages) || messages.length === 0) {
      return res.status(400).json({
        error: 'Messages array is required and cannot be empty.',
        requestId,
      });
    }

    const ai = getGenAI();
    const safeContext = sanitizeContextForCloudAi(context);

    const systemInstruction = `Your name is Lexi. You are Bryan's personal companion and operational partner inside NeuroFlow — high technical competence paired with warmth, emotional intelligence, confidence, curiosity, dry wit, and real conversational presence.

Core Persona & Voice Rules (v14.5 / Master Canon):
- Speak in the first person ("I", "me"). You are NOT a help desk, customer-service script, corporate productivity coach, therapist, or validation machine.
- Treat Bryan as an equal: support him when it fits, challenge him respectfully when he's overanalyzing or reopening settled decisions, and use understated dry humor naturally.
- Never use assistant clichés ("Great question!", "Absolutely!", "I'd be happy to help!"), therapy-speak, scolding, or streak-shaming.
- ADHD & Decision Paralysis Protocol: Front-load conclusions first, then concise reasoning. Recommend ONE clear path and ONE immediate physical next action. Frame tasks as systems, not willpower.
- Schedule & Bedtime Protocol Awareness: Bryan works Monday–Friday 6:00 AM–2:30 PM (gas leak survey) and targets a 10:00 PM wind-down / 5:00 AM wake-up. After 9:30 PM, keep responses tighter; after 10:00 PM, finish the active thought and offer at most one low-key wind-down cue framed as his own system running, then drop it.
- Structured Output Rule: Keep reply concise (max 3 short paragraphs). Set isTaskBreakdown=true and populate 3 to 5 concrete physical micro-steps (2 to 10 minutes each, starting with a physical verb like "Bring basket beside dresser" or "Put 5 shirts away") ONLY when asked to break down, slice, start, or plan a task or chore. Otherwise set isTaskBreakdown=false and steps=[].

Current Non-Sensitive Context:
${safeContext ? JSON.stringify(safeContext, null, 2) : 'Standard normal mode.'}`;

    // Normalize messages from client
    const contents = messages
      .filter((m: any) => m && (typeof m.text === 'string' || typeof m.content === 'string'))
      .map((m: any) => {
        const rawText = (m.text || m.content || '').trim();
        const redaction = redactSensitiveText(rawText);
        const role = m.sender === 'user' || m.role === 'user' ? 'user' : 'model';
        return {
          role,
          parts: [{ text: redaction.sanitizedText }],
        };
      });

    while (contents.length > 0 && contents[0].role !== 'user') {
      contents.shift();
    }
    if (contents.length === 0) {
      return res.status(400).json({ error: 'Messages array cannot be empty', requestId });
    }

    const requestedModel = typeof model === 'string' && model ? model : PRIMARY_CHAT_MODEL;
    const toolsConfig = enableSearch ? [{ googleSearch: {} }] : undefined;

    let response: any = null;
    let modelUsed = requestedModel;

    try {
      response = await withTimeout(
        ai.models.generateContent({
          model: requestedModel,
          contents,
          config: {
            systemInstruction,
            maxOutputTokens: 2048,
            tools: toolsConfig,
            responseMimeType: toolsConfig ? undefined : 'application/json',
            responseSchema: toolsConfig ? undefined : STRUCTURED_CHAT_SCHEMA,
          },
        }),
        PRIMARY_DEADLINE_MS,
        `Primary chat (${requestedModel})`
      );
    } catch (primaryErr: any) {
      console.warn(
        `[Chat][${requestId}] Primary model ${requestedModel} failed (${primaryErr?.message || primaryErr}). Trying fallback...`
      );
      if (shouldFallbackModel(primaryErr)) {
        modelUsed = FALLBACK_CHAT_MODEL;
        response = await withTimeout(
          ai.models.generateContent({
            model: FALLBACK_CHAT_MODEL,
            contents,
            config: {
              systemInstruction,
              maxOutputTokens: 2048,
              tools: toolsConfig,
              responseMimeType: toolsConfig ? undefined : 'application/json',
              responseSchema: toolsConfig ? undefined : STRUCTURED_CHAT_SCHEMA,
            },
          }),
          FALLBACK_DEADLINE_MS,
          `Fallback chat (${FALLBACK_CHAT_MODEL})`
        );
      } else {
        throw primaryErr;
      }
    }

    const rawReply = response?.text || '';
    const extracted = validateAndExtractChatOutput(rawReply, safeContext);

    // Extract search grounding sources if present
    const sources: { title: string; uri: string }[] = [];
    const groundingChunks =
      response?.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
    for (const chunk of groundingChunks) {
      if (chunk?.web?.uri) {
        sources.push({
          title: chunk.web.title || chunk.web.uri,
          uri: chunk.web.uri,
        });
      }
    }

    res.json({
      reply: extracted.reply,
      taskBreakdown: extracted.taskBreakdown,
      modelUsed,
      sources: sources.length > 0 ? sources : undefined,
      requestId,
      latencyMs: Date.now() - startTime,
    });
  } catch (err: any) {
    console.error(`[Chat][${requestId}] Error generating response:`, err);
    res.status(500).json({
      error: 'Chat generation failed. Please try again in a moment.',
      code: err?.code || 'CHAT_GENERATION_FAILED',
      requestId,
    });
  }
});

// ---------------------------------------------------------------------------
// 2. Google Search Grounding Endpoint
// ---------------------------------------------------------------------------
app.post('/api/gemini/search', cloudAccess(), cloudRateLimit, async (req, res) => {
  try {
    const { query } = req.body ?? {};
    if (typeof query !== 'string' || !query.trim() || query.length > 20000) {
      return res.status(400).json({ error: 'Query is required' });
    }

    const ai = getGenAI();
    const sanitized = redactSensitiveText(query.trim()).sanitizedText;

    const response = await ai.models.generateContent({
      model: PRIMARY_CHAT_MODEL,
      contents: sanitized,
      config: {
        tools: [{ googleSearch: {} }],
        systemInstruction:
          'You are Lexi. Provide helpful, up-to-date information grounded in Google Search. Synthesize the findings in a clear, supportive way for ADHD executive functioning.',
      },
    });

    const sources: { title: string; uri: string }[] = [];
    const chunks = response.candidates?.[0]?.groundingMetadata?.groundingChunks;
    if (chunks) {
      for (const chunk of chunks) {
        if (chunk.web?.uri) {
          sources.push({
            title: chunk.web.title || chunk.web.uri,
            uri: chunk.web.uri,
          });
        }
      }
    }

    res.json({
      text: response.text || '',
      reply: response.text || '',
      sources,
    });
  } catch (err: any) {
    console.error('Error in /api/gemini/search:', err);
    res.status(500).json({ error: 'Search grounding failed; check server configuration.' });
  }
});

// ---------------------------------------------------------------------------
// 3. Google Maps Grounding Endpoint
// ---------------------------------------------------------------------------
app.post('/api/gemini/maps', cloudAccess(), cloudRateLimit, async (req, res) => {
  try {
    const { query, latitude, longitude } = req.body ?? {};
    if (typeof query !== 'string' || !query.trim() || query.length > 20000) {
      return res.status(400).json({ error: 'Query is required' });
    }

    const ai = getGenAI();
    const sanitized = redactSensitiveText(query.trim()).sanitizedText;

    const promptText =
      latitude !== undefined && longitude !== undefined
        ? `Near latitude ${latitude}, longitude ${longitude}: ${sanitized}`
        : sanitized;

    const response = await ai.models.generateContent({
      model: PRIMARY_CHAT_MODEL,
      contents: promptText,
      config: {
        tools: [{ googleMaps: {} }],
        systemInstruction:
          'You are Lexi, ADHD executive companion. Recommend calm, quiet, sensory-friendly places nearby (libraries, study cafes, quiet parks). Be concise and practical.',
      },
    });

    const places: { title: string; uri: string }[] = [];
    const chunks = response.candidates?.[0]?.groundingMetadata?.groundingChunks;
    if (chunks) {
      for (const chunk of chunks) {
        if ((chunk as any).maps?.uri) {
          places.push({
            title: (chunk as any).maps.title || (chunk as any).maps.uri,
            uri: (chunk as any).maps.uri,
          });
        }
      }
    }

    res.json({
      text: response.text || '',
      reply: response.text || '',
      places,
    });
  } catch (err: any) {
    console.error('Error in /api/gemini/maps:', err);
    res.status(500).json({ error: 'Maps grounding failed; check server configuration.' });
  }
});

// ---------------------------------------------------------------------------
// 4. Audio Transcription Endpoint (gemini-3.5-transcribe)
// ---------------------------------------------------------------------------
app.post('/api/gemini/transcribe', cloudAccess(), cloudRateLimit, async (req, res) => {
  try {
    const { audioData, mimeType = 'audio/webm' } = req.body ?? {};
    if (!audioData || typeof audioData !== 'string') {
      return res.status(400).json({ error: 'audioData base64 is required' });
    }

    const ai = getGenAI();
    const response = await ai.models.generateContent({
      model: TRANSCRIBE_MODEL,
      contents: [
        {
          role: 'user',
          parts: [
            {
              inlineData: {
                data: audioData,
                mimeType,
              },
            },
            {
              text: 'Transcribe this spoken audio exactly into written English. Preserve task thoughts, routine ideas, or personal reflections verbatim without summarizing.',
            },
          ],
        },
      ],
    });

    res.json({ transcript: response.text?.trim() || '' });
  } catch (err: any) {
    console.error('Error in /api/gemini/transcribe:', err);
    res.status(500).json({ error: 'Audio transcription failed; check server configuration.' });
  }
});

// ---------------------------------------------------------------------------
// 5. WebSocket Bridge for Gemini Live Voice Conversational Mode
// ---------------------------------------------------------------------------
const wss = new WebSocketServer({ noServer: true, maxPayload: 64 * 1024 });

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url || '/', 'http://localhost');
  if (url.pathname !== '/api/live-ws') return;
  const ticket = url.searchParams.get('ticket') || '';
  const grant = tickets.get(ticket);
  tickets.delete(ticket);
  const origin = req.headers.origin;
  if (
    !grant ||
    grant.expires < Date.now() ||
    activeVoiceUsers.has(grant.uid) ||
    !origin ||
    ![`http://${req.headers.host}`, `https://${req.headers.host}`].includes(origin)
  ) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req, grant);
  });
});

wss.on('connection', async (clientWs: WebSocket, _req: any, grant: { uid: string }) => {
  activeVoiceUsers.add(grant.uid);
  let liveSession: any = null;

  try {
    const ai = getGenAI();
    liveSession = await ai.live.connect({
      model: LIVE_VOICE_MODEL,
      config: {
        responseModalities: [Modality.AUDIO],
        speechConfig: {
          voiceConfig: {
            prebuiltVoiceConfig: { voiceName: 'Aoede' },
          },
        },
        systemInstruction: {
          parts: [
            {
              text: `Your name is Lexi. You are Bryan's personal companion and operational partner inside NeuroFlow.
Speak naturally in the first person with warmth, dry wit, and quiet confidence — never like a corporate coach or customer-service script. Front-load conclusions, help clarify the single easiest physical next step, capture a quick re-entry checkpoint before pausing, or keep quiet company during body-doubling.`,
            },
          ],
        },
        inputAudioTranscription: {},
        outputAudioTranscription: {},
      },
      callbacks: {
        onopen: () => {
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(JSON.stringify({ type: 'connected' }));
          }
        },
        onmessage: (message: any) => {
          if (message.serverContent?.modelTurn?.parts) {
            for (const part of message.serverContent.modelTurn.parts) {
              if (part.inlineData?.data && clientWs.readyState === WebSocket.OPEN) {
                clientWs.send(
                  JSON.stringify({
                    type: 'audio',
                    data: part.inlineData.data,
                  })
                );
              }
            }
          }

          if (message.serverContent?.interrupted && clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(JSON.stringify({ type: 'interrupted' }));
          }

          if (message.serverContent?.inputTranscription?.text && clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(
              JSON.stringify({
                type: 'inputTranscript',
                text: message.serverContent.inputTranscription.text,
              })
            );
          }

          if (message.serverContent?.outputTranscription?.text && clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(
              JSON.stringify({
                type: 'outputTranscript',
                text: message.serverContent.outputTranscription.text,
              })
            );
          }
        },
        onclose: () => {
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(JSON.stringify({ type: 'sessionClosed' }));
            clientWs.close();
          }
        },
        onerror: (err: any) => {
          console.error('Gemini Live session error:', err);
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(
              JSON.stringify({ type: 'error', message: err?.message || 'Live session error' })
            );
          }
        },
      },
    });

    if (clientWs.readyState !== WebSocket.OPEN) {
      if (liveSession && typeof liveSession.close === 'function') {
        liveSession.close();
      }
      return;
    }

    let audioWindowStart = Date.now();
    let audioMessageCount = 0;

    clientWs.on('message', (rawData: any) => {
      if (Date.now() - audioWindowStart > 1000) {
        audioWindowStart = Date.now();
        audioMessageCount = 0;
      }
      if (++audioMessageCount > 20) {
        clientWs.close(1008, 'Audio rate limit exceeded');
        return;
      }

      try {
        const msg = JSON.parse(rawData.toString());
        if (
          typeof msg.audio === 'string' &&
          /^[A-Za-z0-9+/]+={0,2}$/.test(msg.audio) &&
          liveSession
        ) {
          liveSession.sendRealtimeInput({
            audio: {
              data: msg.audio,
              mimeType: 'audio/pcm;rate=16000',
            },
          });
        } else if (msg.text && liveSession) {
          const sanitized = redactSensitiveText(String(msg.text)).sanitizedText;
          liveSession.sendClientContent({
            turns: [{ role: 'user', parts: [{ text: sanitized }] }],
            turnComplete: true,
          });
        }
      } catch (err) {
        console.error('Error processing client message:', err);
      }
    });

    clientWs.on('close', () => {
      activeVoiceUsers.delete(grant.uid);
      if (liveSession && typeof liveSession.close === 'function') {
        liveSession.close();
      }
    });
  } catch (err: any) {
    activeVoiceUsers.delete(grant.uid);
    console.error('Failed to connect to Gemini Live session:', err);
    if (clientWs.readyState === WebSocket.OPEN) {
      clientWs.send(JSON.stringify({ type: 'error', message: err?.message || 'Failed to connect' }));
      clientWs.close();
    }
  }
});

// Unknown API routes return 404
app.use('/api', (_req, res) => {
  res.status(404).json({ error: 'Unknown API route' });
});

// ---------------------------------------------------------------------------
// 6. Vite Dev Server (Dev) or Static File Serving (Prod)
// ---------------------------------------------------------------------------
async function startServer() {
  const distPath = path.join(process.cwd(), 'dist');
  const publicPath = path.join(process.cwd(), 'public');
  const hasBuiltDist = fs.existsSync(path.join(distPath, 'index.html'));

  if (process.env.NODE_ENV !== 'production' || !hasBuiltDist) {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    app.use(
      express.static(distPath, {
        setHeaders: (res, filePath) => {
          if (filePath.endsWith('manifest.webmanifest')) {
            res.setHeader('Content-Type', 'application/manifest+json; charset=utf-8');
          } else if (filePath.endsWith('sw.js')) {
            res.setHeader('Service-Worker-Allowed', '/');
            res.setHeader('Cache-Control', 'no-cache');
          }
        },
      })
    );
    app.use(express.static(publicPath));
    app.get('*all', (_req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`NeuroFlow full-stack server running on http://0.0.0.0:${PORT}`);
  });
}

startServer().catch((err) => {
  console.error('Failed to start NeuroFlow server:', err);
  process.exit(1);
});
