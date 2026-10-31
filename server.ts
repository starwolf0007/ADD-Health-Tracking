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

// ---------------------------------------------------------------------------
// 1. Multi-Turn Gemini Chatbot Endpoint
// ---------------------------------------------------------------------------
app.post('/api/gemini/chat', async (req, res) => {
  try {
    const { messages, model = 'gemini-3.8-flash', systemInstruction } = req.body;

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
    const contents = (messages || []).map((m: { role: string; content: string }) => ({
      role: m.role === 'assistant' || m.role === 'lexi' ? 'model' : 'user',
      parts: [{ text: m.content }],
    }));

    if (contents.length === 0) {
      return res.status(400).json({ error: 'Messages array cannot be empty' });
    }

    const chosenModel = ['gemini-4-argon', 'gemini-3.8-flash', 'gemini-3.1-flash-lite'].includes(
      model
    )
      ? model
      : 'gemini-3.8-flash';

    const response = await ai.models.generateContent({
      model: chosenModel,
      contents,
      config: {
        systemInstruction: defaultSystemInstruction,
      },
    });

    const reply = response.text || '';
    res.json({ reply, model: chosenModel });
  } catch (err: any) {
    console.error('Error in /api/gemini/chat:', err);
    res.status(500).json({ error: err.message || 'Chat generation failed' });
  }
});

// ---------------------------------------------------------------------------
// 2. Google Search Grounding Endpoint (gemini-3.8-flash)
// ---------------------------------------------------------------------------
app.post('/api/gemini/search', async (req, res) => {
  try {
    const { query } = req.body;
    if (!query) {
      return res.status(400).json({ error: 'Query is required' });
    }

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

    // Extract search web sources
    const sources = groundingChunks
      .map((c: any) => c.web)
      .filter((w: any) => w && w.uri);

    res.json({ text, sources });
  } catch (err: any) {
    console.error('Error in /api/gemini/search:', err);
    res.status(500).json({ error: err.message || 'Search grounding failed' });
  }
});

// ---------------------------------------------------------------------------
// 3. Google Maps Grounding Endpoint (gemini-3.8-flash)
// ---------------------------------------------------------------------------
app.post('/api/gemini/maps', async (req, res) => {
  try {
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
    res.status(500).json({ error: err.message || 'Maps grounding failed' });
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
