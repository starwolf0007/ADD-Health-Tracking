import {
  cloudAccess,
  cloudRateLimit,
  preAuthRateLimit,
} from './server/cloudAccess';
import { randomUUID } from 'node:crypto';
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
const ai = process.env.GEMINI_API_KEY
  ? new GoogleGenAI({
      apiKey: process.env.GEMINI_API_KEY,
      httpOptions: {
        headers: {
          'User-Agent': 'aistudio-build',
        },
      },
    })
  : null;

app.use('/api', preAuthRateLimit);
app.use('/api/gemini', cloudAccess(), cloudRateLimit);
app.use(express.json({ limit: '25mb' }));
app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));

// ---------------------------------------------------------------------------
// 1. Multi-Turn Gemini Chatbot Endpoint
// ---------------------------------------------------------------------------
app.post('/api/gemini/chat', async (req, res) => {
  try {
    const {
      messages,
      model = 'gemini-3.8-flash',
      systemInstruction,
    } = req.body ?? {};
    if (
      !Array.isArray(messages) ||
      messages.length === 0 ||
      messages.length > 100 ||
      messages.some(
        (message: any) =>
          !message ||
          typeof message.content !== 'string' ||
          message.content.length > 20000 ||
          !['user', 'assistant', 'lexi'].includes(message.role),
      )
    ) {
      return res.status(400).json({
        error: 'Provide 1–100 valid messages, each under 20000 characters.',
      });
    }

    if (
      systemInstruction !== undefined &&
      (typeof systemInstruction !== 'string' || systemInstruction.length > 6000)
    ) {
      return res.status(400).json({ error: 'Invalid system instruction' });
    }
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
    const contents = (messages || []).map(
      (m: { role: string; content: string }) => ({
        role: m.role === 'assistant' || m.role === 'lexi' ? 'model' : 'user',
        parts: [{ text: m.content }],
      }),
    );

    if (contents.length === 0) {
      return res.status(400).json({ error: 'Messages array cannot be empty' });
    }

    const chosenModel = [
      'gemini-4-argon',
      'gemini-3.8-flash',
      'gemini-3.1-flash-lite',
    ].includes(model)
      ? model
      : 'gemini-3.8-flash';

    const response = await ai!.models.generateContent({
      model: chosenModel,
      contents,
      config: {
        systemInstruction: defaultSystemInstruction,
        maxOutputTokens: 2048,
      },
    });

    const reply = response.text || '';
    res.json({ reply, model: chosenModel });
  } catch (err: any) {
    console.error('Error in /api/gemini/chat:', err);
    res
      .status(500)
      .json({ error: 'Chat generation failed; check server configuration.' });
  }
});

// ---------------------------------------------------------------------------
// 2. Google Search Grounding Endpoint (gemini-3.8-flash)
// ---------------------------------------------------------------------------
app.post('/api/gemini/search', async (req, res) => {
  try {
    const { query } = req.body ?? {};
    if (typeof query !== 'string' || !query.trim() || query.length > 20000) {
      return res.status(400).json({ error: 'Query is required' });
    }

    const response = await ai!.models.generateContent({
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

    // Extract search web sources
    const sources = groundingChunks
      .map((c: any) => c.web)
      .filter((w: any) => w && w.uri);

    res.json({ text, sources });
  } catch (err: any) {
    console.error('Error in /api/gemini/search:', err);
    res
      .status(500)
      .json({ error: 'Search grounding failed; check server configuration.' });
  }
});

// ---------------------------------------------------------------------------
// 3. Google Maps Grounding Endpoint (gemini-3.8-flash)
// ---------------------------------------------------------------------------
app.post('/api/gemini/maps', async (req, res) => {
  try {
    const { query, latitude, longitude } = req.body ?? {};
    if (typeof query !== 'string' || !query.trim() || query.length > 20000) {
      return res.status(400).json({ error: 'Query is required' });
    }

    if (
      (latitude !== undefined || longitude !== undefined) &&
      (typeof latitude !== 'number' ||
        typeof longitude !== 'number' ||
        !Number.isFinite(latitude) ||
        !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 ||
        Math.abs(longitude) > 180)
    ) {
      return res.status(400).json({ error: 'Invalid coordinates' });
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

    const response = await ai!.models.generateContent({
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

    // Extract place cards & map links
    const places = groundingChunks
      .filter((c: any) => c.maps)
      .map((c: any) => ({
        title: c.maps.title || 'Location',
        uri: c.maps.uri || '',
        placeAnswerSources: c.maps.placeAnswerSources || null,
      }));

    res.json({ text, places });
  } catch (err: any) {
    console.error('Error in /api/gemini/maps:', err);
    res
      .status(500)
      .json({ error: 'Maps grounding failed; check server configuration.' });
  }
});

// ---------------------------------------------------------------------------
// 4. Audio Transcription Endpoint (gemini-3.5-transcribe)
// ---------------------------------------------------------------------------
app.post('/api/gemini/transcribe', async (req, res) => {
  try {
    const { audioData, mimeType = 'audio/webm' } = req.body ?? {};
    if (
      typeof audioData !== 'string' ||
      audioData.length > 20_000_000 ||
      !/^[A-Za-z0-9+/]+={0,2}$/.test(audioData)
    ) {
      return res.status(400).json({ error: 'Audio data is required' });
    }

    if (
      ![
        'audio/webm',
        'audio/ogg',
        'audio/mp4',
        'audio/wav',
        'audio/mpeg',
      ].includes(mimeType)
    ) {
      return res.status(400).json({ error: 'Unsupported audio type' });
    }
    const audioPart = {
      inlineData: {
        mimeType,
        data: audioData,
      },
    };

    const response = await ai!.models.generateContent({
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
    res.status(500).json({
      error: 'Audio transcription failed; check server configuration.',
    });
  }
});

// ---------------------------------------------------------------------------
// 5. Live Voice WebSocket (gemini-3.8-live)
// ---------------------------------------------------------------------------
const tickets = new Map<string, { uid: string; expires: number }>();
const activeVoiceUsers = new Set<string>();
app.post('/api/gemini/live-ticket', (_req, res) => {
  for (const [key, value] of tickets)
    if (value.expires < Date.now()) tickets.delete(key);
  if (tickets.size >= 1000)
    return res.status(503).json({ error: 'Voice is busy. Try again shortly.' });
  const ticket = randomUUID();
  tickets.set(ticket, { uid: res.locals.uid, expires: Date.now() + 30_000 });
  res.json({ ticket });
});
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
    ![`http://${req.headers.host}`, `https://${req.headers.host}`].includes(
      origin,
    )
  ) {
    socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n');
    return;
  }
  activeVoiceUsers.add(grant.uid);
  wss.handleUpgrade(req, socket, head, (ws) => {
    const timeout = setTimeout(
      () => ws.close(1000, 'Session limit reached'),
      5 * 60_000,
    );
    ws.once('close', () => {
      clearTimeout(timeout);
      activeVoiceUsers.delete(grant.uid);
    });
    wss.emit('connection', ws);
  });
});

wss.on('connection', async (clientWs: WebSocket) => {
  console.log('Client connected to Live Voice API WebSocket');

  let liveSession: any = null;

  try {
    liveSession = await ai!.live.connect({
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
              }),
            );
          }

          if (message.serverContent?.outputTranscription?.text) {
            clientWs.send(
              JSON.stringify({
                type: 'outputTranscript',
                text: message.serverContent.outputTranscription.text,
              }),
            );
          }

          // Check for audio chunks (24kHz PCM)
          for (const part of message.serverContent?.modelTurn?.parts ?? []) {
            if (part.inlineData?.data) {
              clientWs.send(
                JSON.stringify({
                  type: 'audio',
                  data: part.inlineData.data,
                }),
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
            clientWs.send(
              JSON.stringify({ type: 'error', message: err.message }),
            );
          }
        },
      },
    });

    if (clientWs.readyState !== WebSocket.OPEN) {
      liveSession.close();
      return;
    }
    clientWs.send(JSON.stringify({ type: 'connected' }));

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
        const parsed = JSON.parse(rawData.toString());
        if (
          typeof parsed.audio === 'string' &&
          /^[A-Za-z0-9+/]+={0,2}$/.test(parsed.audio) &&
          liveSession
        ) {
          // Send 16kHz PCM audio chunk
          liveSession.sendRealtimeInput({
            audio: {
              data: parsed.audio,
              mimeType: 'audio/pcm;rate=16000',
            },
          });
        }
      } catch (err) {
        console.error('Error processing client audio message:', err);
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
    app.use('/api', (_req, res) => {
      res.status(404).json({ error: 'Unknown API route' });
    });
    const distPath = path.resolve(__dirname, 'dist');
    app.use(express.static(distPath));
    app.get('/{*path}', (_req, res) => {
      res.sendFile(path.resolve(distPath, 'index.html'));
    });
  }

  const PORT = Number(process.env.PORT || 3000);
  const HOST = '0.0.0.0';

  server.listen(PORT, HOST, () => {
    console.log(
      `NeuroFlow full-stack server running on http://${HOST}:${PORT}`,
    );
  });
}

startServer().catch((err) => {
  console.error('Failed to start server:', err);
  process.exit(1);
});
