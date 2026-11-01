import express from 'express';
import http from 'http';
import { WebSocketServer, WebSocket } from 'ws';
import path from 'path';
import { fileURLToPath } from 'url';
import { GoogleGenAI, Modality } from '@google/genai';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const server = http.createServer(app);

// Initialize Gemini SDK with telemetry header
const ai = new GoogleGenAI({
  apiKey: process.env.GEMINI_API_KEY,
  httpOptions: {
    headers: {
      'User-Agent': 'aistudio-build',
    },
  },
});

app.use(express.json({ limit: '25mb' }));

function shouldFallbackModel(err: any): boolean {
  const msg = typeof err?.message === 'string' ? err.message : JSON.stringify(err || '');
  return (
    err?.status === 429 ||
    err?.code === 429 ||
    err?.status === 503 ||
    err?.code === 503 ||
    msg.includes('429') ||
    msg.includes('503') ||
    msg.includes('UNAVAILABLE') ||
    msg.includes('high demand') ||
    msg.includes('RESOURCE_EXHAUSTED') ||
    msg.includes('quota') ||
    msg.includes('timeout') ||
    msg.includes('TIMEOUT') ||
    msg.includes('deadline')
  );
}

function withTimeout<T>(promise: Promise<T>, ms: number, description: string): Promise<T> {
  let timer: any;
  const timeoutPromise = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(new Error(`${description} timed out after ${ms}ms`));
    }, ms);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => {
    clearTimeout(timer);
  });
}

// ---------------------------------------------------------------------------
// 1. Multi-Turn Gemini Chatbot Endpoint
// ---------------------------------------------------------------------------
app.post('/api/gemini/chat', async (req, res) => {
  const reqId = (req.headers['x-request-id'] as string) || `req_${Date.now()}_${Math.random().toString(36).substring(2, 6)}`;
  let clientAborted = false;

  res.on('close', () => {
    if (!res.writableEnded) {
      clientAborted = true;
    }
  });

  const { messages, model = 'gemini-3.1-flash-lite', systemInstruction } = req.body;
  console.log(`[${reqId}] /api/gemini/chat received. Requested model: ${model}`);

  const defaultSystemInstruction =
    systemInstruction ||
    `You are Lexi, an empathetic, calm, and practical ADHD executive function companion.
Your role:
- Reduce initiation friction and cognitive overwhelm.
- Offer absurdly small, concrete first physical steps.
- Respect user capacity and energy levels (low, medium, high).
- Never use shame, guilt, or pressure.
- When helping with tasks, break them into clear, gentle micro-steps.
- Keep responses concise, supportive, and conversational.`;

  // Map conversation history into Gemini format
  const rawContents = (messages || []).map((m: { role: string; content: string }) => ({
    role: m.role === 'assistant' || m.role === 'lexi' ? 'model' : 'user',
    parts: [{ text: m.content }],
  }));

  if (rawContents.length === 0) {
    return res.status(400).json({ error: 'Messages array cannot be empty', reqId });
  }

  // Ensure multi-turn conversation starts with a user turn
  let contents = rawContents;
  while (contents.length > 0 && contents[0].role === 'model') {
    contents = contents.slice(1);
  }
  if (contents.length === 0) {
    contents = [{ role: 'user', parts: [{ text: 'Hello Lexi' }] }];
  }

  const requestedModel = ['gemini-4-argon', 'gemini-3.8-flash', 'gemini-3.1-flash-lite'].includes(model)
    ? model
    : 'gemini-3.1-flash-lite';

  // Try requested model first, then fast gemini-3.1-flash-lite fallback
  const modelsToTry = [requestedModel];
  if (requestedModel !== 'gemini-3.1-flash-lite') {
    modelsToTry.push('gemini-3.1-flash-lite');
  }

  let lastError: any = null;

  for (const currentModel of modelsToTry) {
    if (clientAborted) {
      console.log(`[${reqId}] Client aborted connection before model ${currentModel} completed.`);
      return;
    }

    const timeoutMs = currentModel === 'gemini-3.1-flash-lite' ? 14000 : 8000;
    const startMs = Date.now();

    try {
      console.log(`[${reqId}] Calling model ${currentModel} (timeout ${timeoutMs}ms)...`);
      const response = await withTimeout(
        ai.models.generateContent({
          model: currentModel,
          contents,
          config: {
            systemInstruction: defaultSystemInstruction,
          },
        }),
        timeoutMs,
        `Model ${currentModel}`
      );

      const elapsed = Date.now() - startMs;
      const reply = response.text || '';
      console.log(`[${reqId}] Model ${currentModel} completed in ${elapsed}ms. Reply length: ${reply.length}`);

      if (clientAborted) return;
      return res.json({ reply, model: currentModel, reqId });
    } catch (err: any) {
      const elapsed = Date.now() - startMs;
      lastError = err;
      console.warn(`[${reqId}] Model ${currentModel} failed in ${elapsed}ms (${err?.message || err}).`);

      if (shouldFallbackModel(err)) {
        continue;
      }
      break;
    }
  }

  if (clientAborted) return;

  const isQuota = shouldFallbackModel(lastError);
  console.warn(`[${reqId}] All model attempts failed. Returning error to client.`);
  return res.status(isQuota ? 429 : 500).json({
    error: isQuota
      ? 'Lexi is catching her breath! Gemini API rate limit or high demand reached. Please wait a moment and try again.'
      : (lastError?.message || 'Chat generation failed'),
    isQuota,
    reqId,
  });
});

// ---------------------------------------------------------------------------
// 2. Google Search Grounding Endpoint (gemini-3.8-flash)
// ---------------------------------------------------------------------------
app.post('/api/gemini/search', async (req, res) => {
  const { query } = req.body;
  if (!query) {
    return res.status(400).json({ error: 'Query is required' });
  }

  try {
    const response = await ai.models.generateContent({
      model: 'gemini-3.8-flash',
      contents: query,
      config: {
        tools: [{ googleSearch: {} }],
        systemInstruction:
          'You are Lexi. Provide helpful, up-to-date information grounded in Google Search. Synthesize the findings in a clear, supportive way for ADHD executive functioning.',
      },
    });

    const text = response.text || '';
    const groundingChunks =
      response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];

    const sources = groundingChunks
      .map((c: any) => c.web)
      .filter((w: any) => w && w.uri);

    return res.json({ text, sources });
  } catch (err: any) {
    console.warn('Search grounding error/quota:', err?.message || err);

    // If quota or rate limit, fall back to answering without search tool
    if (isQuotaError(err)) {
      try {
        const fallbackResponse = await ai.models.generateContent({
          model: 'gemini-3.1-flash-lite',
          contents: query,
          config: {
            systemInstruction:
              'You are Lexi. Provide a helpful, clear, and supportive response for ADHD executive functioning.',
          },
        });
        return res.json({
          text: fallbackResponse.text || '',
          sources: [],
          notice: 'Search grounding quota exceeded. Responded using general knowledge.',
        });
      } catch (fallbackErr) {
        // Fall through
      }
    }

    return res.status(isQuotaError(err) ? 429 : 500).json({
      error: isQuotaError(err)
        ? 'Search quota exceeded. Please try again in a few moments.'
        : (err.message || 'Search grounding failed'),
      isQuota: isQuotaError(err),
    });
  }
});

// ---------------------------------------------------------------------------
// 3. Google Maps Grounding Endpoint (gemini-3.8-flash)
// ---------------------------------------------------------------------------
app.post('/api/gemini/maps', async (req, res) => {
  const { query, latitude, longitude } = req.body;
  if (!query) {
    return res.status(400).json({ error: 'Query is required' });
  }

  const toolConfig: any = {};
  if (latitude !== undefined && longitude !== undefined) {
    toolConfig.retrievalConfig = {
      latLng: {
        latitude: Number(latitude),
        longitude: Number(longitude),
      },
    };
  }

  try {
    const response = await ai.models.generateContent({
      model: 'gemini-3.8-flash',
      contents: query,
      config: {
        tools: [{ googleMaps: {} }],
        toolConfig: Object.keys(toolConfig).length > 0 ? toolConfig : undefined,
        systemInstruction:
          'You are Lexi. Assist the user in finding quiet study spaces, gyms, sensory-friendly coffee shops, or libraries based on Google Maps data.',
      },
    });

    const text = response.text || '';
    const groundingChunks =
      response.candidates?.[0]?.groundingMetadata?.groundingChunks || [];

    const places = groundingChunks
      .filter((c: any) => c.maps)
      .map((c: any) => ({
        title: c.maps.title || 'Location',
        uri: c.maps.uri || '',
        placeAnswerSources: c.maps.placeAnswerSources || null,
      }));

    return res.json({ text, places });
  } catch (err: any) {
    console.warn('Maps grounding hit error or quota limit:', err?.message || err);

    // If quota or rate limit, fall back gracefully to helpful general quiet space advice
    if (isQuotaError(err)) {
      try {
        const fallbackResponse = await ai.models.generateContent({
          model: 'gemini-3.1-flash-lite',
          contents: `Suggest sensory-friendly quiet spaces, calm public libraries, and low-distraction environments for someone with ADHD looking for: "${query}". Provide practical criteria for choosing a quiet spot.`,
          config: {
            systemInstruction:
              'You are Lexi. Provide warm, practical advice for finding sensory-friendly quiet places to work or study.',
          },
        });

        return res.json({
          text: fallbackResponse.text || '',
          places: [],
          notice: 'Live Maps grounding quota temporarily exhausted. Showing sensory-friendly location advice.',
        });
      } catch (fallbackErr) {
        // Fall through
      }
    }

    return res.status(isQuotaError(err) ? 429 : 500).json({
      error: isQuotaError(err)
        ? 'Google Maps quota reached. Please wait a few moments and try again.'
        : (err.message || 'Maps grounding failed'),
      isQuota: isQuotaError(err),
    });
  }
});


// ---------------------------------------------------------------------------
// 4. Audio Transcription Endpoint (gemini-3.5-transcribe)
// ---------------------------------------------------------------------------
app.post('/api/gemini/transcribe', async (req, res) => {
  try {
    const { audioData, mimeType = 'audio/webm' } = req.body;
    if (!audioData) {
      return res.status(400).json({ error: 'Audio data is required' });
    }

    const audioPart = {
      inlineData: {
        mimeType,
        data: audioData,
      },
    };

    const response = await ai.models.generateContent({
      model: 'gemini-3.5-transcribe',
      contents: {
        parts: [
          audioPart,
          {
            text: 'Transcribe this spoken audio accurately. Output only the transcribed text without extra chatter.',
          },
        ],
      },
    });

    const transcript = response.text?.trim() || '';
    res.json({ transcript });
  } catch (err: any) {
    console.error('Error in /api/gemini/transcribe:', err);
    res.status(500).json({ error: err.message || 'Audio transcription failed' });
  }
});

// ---------------------------------------------------------------------------
// 5. Live Voice WebSocket (gemini-3.8-live)
// ---------------------------------------------------------------------------
const wss = new WebSocketServer({ server, path: '/api/live-ws' });

wss.on('connection', async (clientWs: WebSocket) => {
  console.log('Client connected to Live Voice API WebSocket');

  let liveSession: any = null;

  try {
    liveSession = await ai.live.connect({
      model: 'gemini-3.8-live',
      config: {
        responseModalities: [Modality.AUDIO],
        speechConfig: {
          voiceConfig: { prebuiltVoiceConfig: { voiceName: 'Zephyr' } },
        },
        inputAudioTranscription: {},
        outputAudioTranscription: {},
        systemInstruction:
          'You are Lexi speaking directly to the user in a calm, gentle, encouraging voice. Help them navigate their tasks, overcome inertia, and feel supported in their executive function.',
      },
      callbacks: {
        onmessage: (message: any) => {
          if (clientWs.readyState !== WebSocket.OPEN) return;

          // Check for input/output transcriptions
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

          // Check for audio chunks (24kHz PCM)
          for (const part of message.serverContent?.modelTurn?.parts ?? []) {
            if (part.inlineData?.data) {
              clientWs.send(
                JSON.stringify({
                  type: 'audio',
                  data: part.inlineData.data,
                })
              );
            }
          }

          // Check for interruption signal
          if (message.serverContent?.interrupted) {
            clientWs.send(JSON.stringify({ type: 'interrupted' }));
          }
        },
        onclose: () => {
          console.log('Gemini Live session closed');
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(JSON.stringify({ type: 'sessionClosed' }));
          }
        },
        onerror: (err: any) => {
          console.error('Gemini Live session error:', err);
          if (clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(JSON.stringify({ type: 'error', message: err.message }));
          }
        },
      },
    });

    clientWs.send(JSON.stringify({ type: 'connected' }));

    clientWs.on('message', (rawData: any) => {
      try {
        const parsed = JSON.parse(rawData.toString());
        if (parsed.audio && liveSession) {
          // Send 16kHz PCM audio chunk
          liveSession.sendRealtimeInput({
            audio: {
              data: parsed.audio,
              mimeType: 'audio/pcm;rate=16000',
            },
          });
        } else if (parsed.text && liveSession) {
          // Send text input to live session
          liveSession.sendClientContent({
            turns: [
              {
                role: 'user',
                parts: [{ text: parsed.text }],
              },
            ],
            turnComplete: true,
          });
        }
      } catch (err) {
        console.warn('Error processing client audio/text message:', err);
      }
    });

    clientWs.on('close', () => {
      console.log('Client closed WebSocket');
      if (liveSession && typeof liveSession.close === 'function') {
        liveSession.close();
      }
    });
  } catch (err: any) {
    console.error('Failed to connect to Gemini Live session:', err);
    if (clientWs.readyState === WebSocket.OPEN) {
      clientWs.send(JSON.stringify({ type: 'error', message: err.message }));
      clientWs.close();
    }
  }
});

// ---------------------------------------------------------------------------
// 6. Vite Dev Server / Static File Serving
// ---------------------------------------------------------------------------
async function startServer() {
  const isDev = process.env.NODE_ENV !== 'production';

  if (isDev) {
    const { createServer: createViteServer } = await import('vite');
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.resolve(__dirname, 'dist');
    app.use(express.static(distPath));
    app.get('*', (_req, res) => {
      res.sendFile(path.resolve(distPath, 'index.html'));
    });
  }

  const PORT = 3000;
  const HOST = '0.0.0.0';

  server.listen(PORT, HOST, () => {
    console.log(`NeuroFlow full-stack server running on http://${HOST}:${PORT}`);
  });
}

startServer().catch((err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
