import express from 'express';
import { createServer as createViteServer } from 'vite';
import { WebSocketServer, WebSocket } from 'ws';
import { GoogleGenAI, Modality, ThinkingLevel, Type } from '@google/genai';
import path from 'path';
import fs from 'fs';
import http from 'http';
import { redactSensitiveText, sanitizeContextForCloudAi } from './src/lib/privacyGate';

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
  context?: Record<string, any>
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
        if (validSteps.length >= 6) break;
      }

      if (validSteps.length === 0) {
        return {
          reply: cleanReply,
          taskBreakdown: null,
        };
      }

      const inferredTitle =
        (typeof parsed.targetTaskTitle === 'string' && parsed.targetTaskTitle.trim()) ||
        (typeof context?.activeTaskTitle === 'string' && context.activeTaskTitle.trim()) ||
        (typeof context?.activeTask === 'string' && context.activeTask !== 'None'
          ? context.activeTask.trim()
          : 'Current Task');

      const inferredId =
        typeof context?.activeTaskId === 'string' && context.activeTaskId.trim()
          ? context.activeTaskId.trim()
          : undefined;

      return {
        reply: cleanReply,
        taskBreakdown: {
          targetTaskId: inferredId,
          targetTaskTitle: inferredTitle,
          steps: validSteps,
        },
      };
    }
  } catch {
    // Not JSON (e.g. search-grounded response or fallback text). Return plain text safely without fabricating steps.
  }

  return {
    reply: trimmed,
    taskBreakdown: null,
  };
}

/**
 * Verifies authentication/session header and explicit Cloud AI consent before invoking Gemini.
 */
function verifyCloudAiGate(
  req: express.Request,
  res: express.Response,
  requestId: string
): boolean {
  const authHeader = String(req.headers['x-neuroflow-auth'] || '').toLowerCase();
  const authBearer = String(req.headers['authorization'] || '');

  if (
    authHeader === 'unauthenticated' ||
    authHeader === 'denied' ||
    authBearer === 'Bearer invalid'
  ) {
    console.warn(`[Gate][${requestId}] Rejected unauthenticated request to ${req.path}`);
    res.status(401).json({
      error: 'Authentication required to access this protected endpoint.',
      code: 'UNAUTHORIZED',
      requestId,
    });
    return false;
  }

  const consentHeader = String(req.headers['x-cloud-ai-consent'] || '').toLowerCase();
  const bodyConsent = req.body?.cloudAiConsent;

  // Enforce explicit Cloud AI consent (either header x-cloud-ai-consent: true or explicit body flag)
  if (consentHeader === 'false' || bodyConsent === false || consentHeader !== 'true') {
    console.warn(`[Gate][${requestId}] Blocked Cloud AI call: consent=${consentHeader || 'missing'}`);
    res.status(403).json({
      error: 'Cloud AI is disabled. Enable Cloud Gemini in Settings to use cloud intelligence.',
      code: 'CLOUD_AI_DISABLED',
      requestId,
    });
    return false;
  }

  return true;
}

async function startServer() {
  const app = express();
  const server = http.createServer(app);

  app.use(express.json({ limit: '25mb' }));

  // ---------------------------------------------------------------------------
  // 0. Diagnostic Health & Model Probe Endpoint
  // ---------------------------------------------------------------------------
  app.get('/api/gemini/health', (req, res) => {
    const requestId = (req.headers['x-request-id'] as string) || `health-${Date.now()}`;
    res.json({
      ok: true,
      requestId,
      hasApiKey: Boolean(process.env.GEMINI_API_KEY),
      models: {
        primaryChat: PRIMARY_CHAT_MODEL,
        fallbackChat: FALLBACK_CHAT_MODEL,
        transcribe: TRANSCRIBE_MODEL,
        liveVoice: LIVE_VOICE_MODEL,
      },
      deadlinesMs: {
        primary: PRIMARY_DEADLINE_MS,
        fallback: FALLBACK_DEADLINE_MS,
      },
    });
  });

  // ---------------------------------------------------------------------------
  // 1. Lexi Chat & Task Breakdown API (Structured Output + Grounding Support)
  // ---------------------------------------------------------------------------
  app.post('/api/gemini/chat', async (req, res) => {
    const startTime = Date.now();
    const requestId =
      (req.headers['x-request-id'] as string) ||
      req.body?.requestId ||
      `req-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;

    let clientAborted = false;
    res.on('close', () => {
      if (!res.writableEnded) {
        clientAborted = true;
        console.log(
          `[Chat][${requestId}] Client aborted connection after ${Date.now() - startTime}ms`
        );
      }
    });

    if (!verifyCloudAiGate(req, res, requestId)) {
      return;
    }

    try {
      const { messages, context, enableSearch } = req.body || {};
      if (!Array.isArray(messages) || messages.length === 0) {
        res.status(400).json({
          error: 'Messages array is required and cannot be empty.',
          requestId,
        });
        return;
      }

      const ai = getGenAI();

      // Enforce sensitive-data privacy boundary on context and messages
      const safeContext = sanitizeContextForCloudAi(context);
      let redactedCategoriesCount = 0;

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

      const contents = messages
        .filter((m: any) => m && typeof m.text === 'string' && m.text.trim().length > 0)
        .map((m: any) => {
          const redaction = redactSensitiveText(m.text.trim());
          if (redaction.wasRedacted) {
            redactedCategoriesCount += redaction.redactedCategories.length;
          }
          return {
            role: m.sender === 'user' ? 'user' : 'model',
            parts: [{ text: redaction.sanitizedText }],
          };
        });

      while (contents.length > 0 && contents[0].role !== 'user') {
        contents.shift();
      }

      if (contents.length === 0) {
        res.status(400).json({
          error: 'At least one user message with non-empty text is required.',
          requestId,
        });
        return;
      }

      const useSearch = Boolean(enableSearch);
      console.log(
        `[Chat][${requestId}] Starting model call (model=${PRIMARY_CHAT_MODEL}, turns=${contents.length}, search=${useSearch}, redacted=${redactedCategoriesCount})`
      );

      const buildConfig = (modelName: string) => {
        const thinkingConfig =
          modelName === PRIMARY_CHAT_MODEL
            ? { thinkingConfig: { thinkingLevel: ThinkingLevel.LOW } }
            : {};
        if (useSearch) {
          return {
            systemInstruction,
            tools: [{ googleSearch: {} }],
            ...thinkingConfig,
          };
        }
        return {
          systemInstruction,
          responseMimeType: 'application/json',
          responseSchema: STRUCTURED_CHAT_SCHEMA,
          ...thinkingConfig,
        };
      };

      let response;
      let usedModel = PRIMARY_CHAT_MODEL;

      try {
        response = await withTimeout(
          ai.models.generateContent({
            model: PRIMARY_CHAT_MODEL,
            contents,
            config: buildConfig(PRIMARY_CHAT_MODEL),
          }),
          PRIMARY_DEADLINE_MS,
          `Model ${PRIMARY_CHAT_MODEL}`
        );
      } catch (primaryErr: any) {
        if (clientAborted) return;
        if (shouldFallbackModel(primaryErr)) {
          console.warn(
            `[Chat][${requestId}] Primary model ${PRIMARY_CHAT_MODEL} failed (${primaryErr?.status || primaryErr?.code || primaryErr?.message}), falling back to ${FALLBACK_CHAT_MODEL}`
          );
          usedModel = FALLBACK_CHAT_MODEL;
          response = await withTimeout(
            ai.models.generateContent({
              model: FALLBACK_CHAT_MODEL,
              contents,
              config: buildConfig(FALLBACK_CHAT_MODEL),
            }),
            FALLBACK_DEADLINE_MS,
            `Fallback model ${FALLBACK_CHAT_MODEL}`
          );
        } else {
          throw primaryErr;
        }
      }

      if (clientAborted || res.writableEnded) {
        return;
      }

      const chunks =
        response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
      const sources = chunks
        .map((c: any) => c.web)
        .filter((w: any) => w && w.uri && w.title);

      const rawText = response.text || '';
      const validated = validateAndExtractChatOutput(rawText, safeContext);

      const durationMs = Date.now() - startTime;
      console.log(
        `[Chat][${requestId}] Completed (status=200, model=${usedModel}, durationMs=${durationMs}, replyLength=${validated.reply.length}, breakdownSteps=${validated.taskBreakdown?.steps.length || 0})`
      );

      res.json({
        reply: validated.reply,
        taskBreakdown: validated.taskBreakdown,
        sources,
        requestId,
        model: usedModel,
        durationMs,
        privacyRedacted: redactedCategoriesCount > 0,
      });
    } catch (error: any) {
      const durationMs = Date.now() - startTime;
      const status =
        typeof error?.status === 'number' && error.status >= 400 && error.status < 600
          ? error.status
          : 500;
      console.error(
        `[Chat][${requestId}] Failed after ${durationMs}ms (status=${status}):`,
        error?.message || error
      );
      if (!clientAborted && !res.writableEnded) {
        res.status(status).json({
          error: error?.message || 'Failed to generate chat response',
          code: error?.code || 'MODEL_ERROR',
          requestId,
          durationMs,
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // 2. Search Grounded Quick Lookup
  // ---------------------------------------------------------------------------
  app.post('/api/gemini/search', async (req, res) => {
    const startTime = Date.now();
    const requestId =
      (req.headers['x-request-id'] as string) ||
      req.body?.requestId ||
      `search-${Date.now()}`;

    let clientAborted = false;
    res.on('close', () => {
      if (!res.writableEnded) clientAborted = true;
    });

    if (!verifyCloudAiGate(req, res, requestId)) {
      return;
    }

    try {
      const { query } = req.body || {};
      if (!query || typeof query !== 'string' || !query.trim()) {
        res.status(400).json({ error: 'Query is required', requestId });
        return;
      }

      const ai = getGenAI();
      const sanitizedQuery = redactSensitiveText(query.trim()).sanitizedText;

      let response;
      let usedModel = PRIMARY_CHAT_MODEL;
      try {
        response = await withTimeout(
          ai.models.generateContent({
            model: PRIMARY_CHAT_MODEL,
            contents: sanitizedQuery,
            config: {
              tools: [{ googleSearch: {} }],
            },
          }),
          PRIMARY_DEADLINE_MS,
          `Search ${PRIMARY_CHAT_MODEL}`
        );
      } catch (err: any) {
        if (clientAborted) return;
        if (shouldFallbackModel(err)) {
          usedModel = FALLBACK_CHAT_MODEL;
          response = await withTimeout(
            ai.models.generateContent({
              model: FALLBACK_CHAT_MODEL,
              contents: sanitizedQuery,
              config: {
                tools: [{ googleSearch: {} }],
              },
            }),
            FALLBACK_DEADLINE_MS,
            `Search fallback ${FALLBACK_CHAT_MODEL}`
          );
        } else {
          throw err;
        }
      }

      if (clientAborted || res.writableEnded) return;

      const chunks =
        response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
      const sources = chunks
        .map((c: any) => c.web)
        .filter((w: any) => w && w.uri && w.title);

      res.json({
        reply: response.text || '',
        sources,
        requestId,
        model: usedModel,
        durationMs: Date.now() - startTime,
      });
    } catch (error: any) {
      const status =
        typeof error?.status === 'number' && error.status >= 400 && error.status < 600
          ? error.status
          : 500;
      if (!clientAborted && !res.writableEnded) {
        res.status(status).json({
          error: error?.message || 'Failed search grounding',
          requestId,
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // 3. Maps Grounding Lookup (Find nearby quiet spaces / pharmacies / errands)
  // ---------------------------------------------------------------------------
  app.post('/api/gemini/maps', async (req, res) => {
    const startTime = Date.now();
    const requestId =
      (req.headers['x-request-id'] as string) ||
      req.body?.requestId ||
      `maps-${Date.now()}`;

    let clientAborted = false;
    res.on('close', () => {
      if (!res.writableEnded) clientAborted = true;
    });

    if (!verifyCloudAiGate(req, res, requestId)) {
      return;
    }

    try {
      const { query, latitude, longitude } = req.body || {};
      if (!query || typeof query !== 'string' || !query.trim()) {
        res.status(400).json({ error: 'Query is required', requestId });
        return;
      }

      const ai = getGenAI();
      const sanitizedQuery = redactSensitiveText(query.trim()).sanitizedText;

      const config: any = {
        tools: [{ googleMaps: {} }],
      };

      if (latitude !== undefined && longitude !== undefined) {
        config.toolConfig = {
          retrievalConfig: {
            latLng: {
              latitude: Number(latitude),
              longitude: Number(longitude),
            },
          },
        };
      }

      let response;
      let usedModel = 'gemini-2.5-flash';
      try {
        response = await withTimeout(
          ai.models.generateContent({
            model: 'gemini-2.5-flash',
            contents: sanitizedQuery,
            config,
          }),
          PRIMARY_DEADLINE_MS,
          'Maps gemini-2.5-flash'
        );
      } catch (err: any) {
        if (clientAborted) return;
        usedModel = FALLBACK_CHAT_MODEL;
        response = await withTimeout(
          ai.models.generateContent({
            model: FALLBACK_CHAT_MODEL,
            contents: sanitizedQuery,
          }),
          FALLBACK_DEADLINE_MS,
          `Maps fallback ${FALLBACK_CHAT_MODEL}`
        );
      }

      if (clientAborted || res.writableEnded) return;

      const chunks =
        response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];
      const places = chunks
        .map((c: any) => c.maps)
        .filter((m: any) => m && m.uri && m.title);

      res.json({
        reply: response.text || '',
        places,
        requestId,
        model: usedModel,
        durationMs: Date.now() - startTime,
      });
    } catch (error: any) {
      const status =
        typeof error?.status === 'number' && error.status >= 400 && error.status < 600
          ? error.status
          : 500;
      if (!clientAborted && !res.writableEnded) {
        res.status(status).json({
          error: error?.message || 'Failed maps grounding',
          requestId,
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // 4. Audio Transcription API (gemini-3.5-transcribe)
  // ---------------------------------------------------------------------------
  app.post('/api/gemini/transcribe', async (req, res) => {
    const startTime = Date.now();
    const requestId =
      (req.headers['x-request-id'] as string) ||
      req.body?.requestId ||
      `transcribe-${Date.now()}`;

    let clientAborted = false;
    res.on('close', () => {
      if (!res.writableEnded) clientAborted = true;
    });

    if (!verifyCloudAiGate(req, res, requestId)) {
      return;
    }

    try {
      const { audioData, mimeType } = req.body || {};
      if (!audioData) {
        res.status(400).json({ error: 'Missing audioData', requestId });
        return;
      }

      const ai = getGenAI();
      const response = await withTimeout(
        ai.models.generateContent({
          model: TRANSCRIBE_MODEL,
          contents: [
            {
              inlineData: {
                data: audioData,
                mimeType: mimeType || 'audio/webm',
              },
            },
            'Transcribe this spoken note or task accurately. Return only the clean transcription text without extra commentary.',
          ],
        }),
        FALLBACK_DEADLINE_MS,
        `Transcribe ${TRANSCRIBE_MODEL}`
      );

      if (clientAborted || res.writableEnded) return;

      res.json({
        transcript: response.text?.trim() || '',
        requestId,
        durationMs: Date.now() - startTime,
      });
    } catch (error: any) {
      const status =
        typeof error?.status === 'number' && error.status >= 400 && error.status < 600
          ? error.status
          : 500;
      if (!clientAborted && !res.writableEnded) {
        res.status(status).json({
          error: error?.message || 'Failed to transcribe audio',
          requestId,
        });
      }
    }
  });

  // ---------------------------------------------------------------------------
  // 5. WebSocket Bridge for Gemini Live Voice Conversational Mode
  // ---------------------------------------------------------------------------
  const wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (request, socket, head) => {
    const pathname = request.url?.split('?')[0];
    if (pathname === '/api/live-ws') {
      wss.handleUpgrade(request, socket, head, (ws) => {
        wss.emit('connection', ws, request);
      });
    }
  });

  wss.on('connection', async (clientWs: WebSocket) => {
    let session: any = null;
    try {
      const ai = getGenAI();
      session = await ai.live.connect({
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
            if (clientWs.readyState !== WebSocket.OPEN) return;

            const parts = message.serverContent?.modelTurn?.parts;
            if (parts) {
              for (const part of parts) {
                if (part.inlineData?.data) {
                  clientWs.send(
                    JSON.stringify({
                      type: 'audio',
                      data: part.inlineData.data,
                    })
                  );
                }
              }
            }

            if (message.serverContent?.interrupted) {
              clientWs.send(JSON.stringify({ type: 'interrupted' }));
            }

            if (message.serverContent?.inputTranscription?.text) {
              clientWs.send(
                JSON.stringify({
                  type: 'inputTranscript',
                  text: message.serverContent.inputTranscription.text,
                })
              );
            }

            if (message.serverContent?.outputTranscription?.text) {
              clientWs.send(
                JSON.stringify({
                  type: 'outputTranscript',
                  text: message.serverContent.outputTranscription.text,
                })
              );
            }

            if (message.serverContent?.turnComplete) {
              clientWs.send(JSON.stringify({ type: 'turnComplete' }));
            }
          },
          onerror: (err: any) => {
            console.error('Live API error:', err);
            if (clientWs.readyState === WebSocket.OPEN) {
              clientWs.send(
                JSON.stringify({
                  type: 'error',
                  message: err?.message || 'Live API error',
                })
              );
            }
          },
          onclose: () => {
            if (clientWs.readyState === WebSocket.OPEN) {
              clientWs.close();
            }
          },
        },
      });

      clientWs.on('message', (raw: Buffer) => {
        try {
          const msg = JSON.parse(raw.toString());
          if (msg.audio && session) {
            session.sendRealtimeInput({
              audio: {
                data: msg.audio,
                mimeType: 'audio/pcm;rate=16000',
              },
            });
          } else if (msg.text && session) {
            const sanitized = redactSensitiveText(String(msg.text)).sanitizedText;
            session.sendClientContent({
              turns: [{ role: 'user', parts: [{ text: sanitized }] }],
              turnComplete: true,
            });
          }
        } catch (err) {
          console.error('Failed to process client WS message:', err);
        }
      });

      clientWs.on('close', () => {
        if (session) {
          try {
            session.close();
          } catch {}
        }
      });
    } catch (error: any) {
      console.error('Failed to establish Gemini Live session:', error);
      if (clientWs.readyState === WebSocket.OPEN) {
        clientWs.send(
          JSON.stringify({
            type: 'error',
            message: error.message || 'Failed to connect to Gemini Live',
          })
        );
        clientWs.close();
      }
    }
  });

  // ---------------------------------------------------------------------------
  // Health Check & PWA Asset Headers
  // ---------------------------------------------------------------------------
  app.get('/api/health', (_req, res) => {
    res.json({
      status: 'ok',
      version: '0.2.0-v2',
      timestamp: new Date().toISOString(),
    });
  });

  // ---------------------------------------------------------------------------
  // Vite Middleware (Dev) or Static Assets (Prod)
  // ---------------------------------------------------------------------------
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
    console.log(`NeuroFlow server running on http://localhost:${PORT}`);
  });
}

startServer();
