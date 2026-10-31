import { useState, useRef, useEffect, useCallback } from 'react';

// Converts Float32 [-1.0, 1.0] PCM from AudioContext to 16-bit little-endian Base64
function floatTo16BitPCMBase64(float32Array: Float32Array): string {
  const buffer = new ArrayBuffer(float32Array.length * 2);
  const view = new DataView(buffer);
  let offset = 0;
  for (let i = 0; i < float32Array.length; i++, offset += 2) {
    const s = Math.max(-1, Math.min(1, float32Array[i]));
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
  }

  let binary = '';
  const bytes = new Uint8Array(buffer);
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

// Decodes base64 24kHz raw PCM little-endian back to Float32Array
function base64ToFloat32Array(base64: string): Float32Array {
  const binaryString = atob(base64);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  const int16Array = new Int16Array(bytes.buffer);
  const float32Array = new Float32Array(int16Array.length);
  for (let i = 0; i < int16Array.length; i++) {
    float32Array[i] = int16Array[i] / 32768.0;
  }
  return float32Array;
}

export interface LiveVoiceMessage {
  id: string;
  sender: 'user' | 'lexi';
  text: string;
}

export function useLiveVoice() {
  const [isConnected, setIsConnected] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [transcriptHistory, setTranscriptHistory] = useState<LiveVoiceMessage[]>([]);
  const [currentInputText, setCurrentInputText] = useState('');
  const [currentOutputText, setCurrentOutputText] = useState('');
  const [error, setError] = useState<string | null>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const inputCtxRef = useRef<AudioContext | null>(null);
  const outputCtxRef = useRef<AudioContext | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const scriptProcessorRef = useRef<ScriptProcessorNode | null>(null);
  const nextStartTimeRef = useRef<number>(0);
  const activeSourcesRef = useRef<AudioBufferSourceNode[]>([]);

  // Stop output audio queue when interrupted
  const stopPlayback = useCallback(() => {
    activeSourcesRef.current.forEach((src) => {
      try {
        src.stop();
        src.disconnect();
      } catch {}
    });
    activeSourcesRef.current = [];
    if (outputCtxRef.current) {
      nextStartTimeRef.current = outputCtxRef.current.currentTime;
    }
  }, []);

  const playAudioChunk = useCallback((base64Audio: string) => {
    if (!outputCtxRef.current) {
      outputCtxRef.current = new (window.AudioContext || (window as any).webkitAudioContext)({
        sampleRate: 24000,
      });
    }
    const ctx = outputCtxRef.current;
    if (ctx.state === 'suspended') {
      ctx.resume();
    }

    const floatData = base64ToFloat32Array(base64Audio);
    const audioBuffer = ctx.createBuffer(1, floatData.length, 24000);
    audioBuffer.getChannelData(0).set(floatData);

    const source = ctx.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(ctx.destination);

    // Schedule gapless playback
    const now = ctx.currentTime;
    const startTime = Math.max(now, nextStartTimeRef.current);
    source.start(startTime);
    nextStartTimeRef.current = startTime + audioBuffer.duration;

    activeSourcesRef.current.push(source);
    setIsSpeaking(true);

    source.onended = () => {
      activeSourcesRef.current = activeSourcesRef.current.filter((s) => s !== source);
      if (activeSourcesRef.current.length === 0) {
        setIsSpeaking(false);
      }
    };
  }, []);

  const startSession = async () => {
    try {
      setError(null);
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = `${protocol}//${window.location.host}/api/live-ws`;
      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = async () => {
        setIsConnected(true);

        // Setup microphone capture at 16kHz
        try {
          const stream = await navigator.mediaDevices.getUserMedia({
            audio: {
              channelCount: 1,
              sampleRate: 16000,
              echoCancellation: true,
              noiseSuppression: true,
            },
          });
          mediaStreamRef.current = stream;

          const inputCtx = new (window.AudioContext || (window as any).webkitAudioContext)({
            sampleRate: 16000,
          });
          inputCtxRef.current = inputCtx;

          const source = inputCtx.createMediaStreamSource(stream);
          const processor = inputCtx.createScriptProcessor(4096, 1, 1);
          scriptProcessorRef.current = processor;

          processor.onaudioprocess = (e) => {
            if (ws.readyState === WebSocket.OPEN) {
              const inputData = e.inputBuffer.getChannelData(0);
              const base64PCM = floatTo16BitPCMBase64(inputData);
              ws.send(JSON.stringify({ audio: base64PCM }));
            }
          };

          source.connect(processor);
          processor.connect(inputCtx.destination);
          setIsListening(true);
        } catch (micErr: any) {
          console.error('Microphone access failed:', micErr);
          setError('Microphone access denied or unavailable: ' + micErr.message);
        }
      };

      ws.onmessage = (event) => {
        try {
          const msg = JSON.parse(event.data);

          if (msg.type === 'connected') {
            setIsConnected(true);
          } else if (msg.type === 'audio' && msg.data) {
            playAudioChunk(msg.data);
          } else if (msg.type === 'interrupted') {
            stopPlayback();
          } else if (msg.type === 'inputTranscript') {
            setCurrentInputText(msg.text);
            setTranscriptHistory((prev) => [
              ...prev,
              { id: `in-${Date.now()}`, sender: 'user', text: msg.text },
            ]);
          } else if (msg.type === 'outputTranscript') {
            setCurrentOutputText((prev) => (prev ? `${prev} ${msg.text}` : msg.text));
            setTranscriptHistory((prev) => [
              ...prev,
              { id: `out-${Date.now()}`, sender: 'lexi', text: msg.text },
            ]);
          } else if (msg.type === 'error') {
            setError(msg.message);
          }
        } catch (e) {
          console.error('Error handling WebSocket message:', e);
        }
      };

      ws.onclose = () => {
        setIsConnected(false);
        setIsListening(false);
        setIsSpeaking(false);
      };

      ws.onerror = (err) => {
        console.error('Live voice WebSocket error:', err);
        setError('Voice connection lost or unavailable.');
        setIsConnected(false);
      };
    } catch (err: any) {
      setError(err.message || 'Failed to start Live Voice session');
    }
  };

  const endSession = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }
    if (mediaStreamRef.current) {
      mediaStreamRef.current.getTracks().forEach((t) => t.stop());
      mediaStreamRef.current = null;
    }
    if (scriptProcessorRef.current) {
      scriptProcessorRef.current.disconnect();
      scriptProcessorRef.current = null;
    }
    if (inputCtxRef.current) {
      inputCtxRef.current.close();
      inputCtxRef.current = null;
    }
    stopPlayback();
    setIsConnected(false);
    setIsListening(false);
    setIsSpeaking(false);
  }, [stopPlayback]);

  useEffect(() => {
    return () => {
      endSession();
    };
  }, [endSession]);

  return {
    isConnected,
    isSpeaking,
    isListening,
    startSession,
    endSession,
    transcriptHistory,
    currentInputText,
    currentOutputText,
    error,
  };
}
