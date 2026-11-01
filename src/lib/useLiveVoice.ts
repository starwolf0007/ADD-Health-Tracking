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

export type MicStatus = 'idle' | 'requesting' | 'granted' | 'denied' | 'unsupported';

export function useLiveVoice() {
  const [isConnected, setIsConnected] = useState(false);
  const [isSpeaking, setIsSpeaking] = useState(false);
  const [isListening, setIsListening] = useState(false);
  const [micStatus, setMicStatus] = useState<MicStatus>('idle');
  const [micError, setMicError] = useState<string | null>(null);
  const [connectionError, setConnectionError] = useState<string | null>(null);
  const [transcriptHistory, setTranscriptHistory] = useState<LiveVoiceMessage[]>([]);
  const [currentInputText, setCurrentInputText] = useState('');
  const [currentOutputText, setCurrentOutputText] = useState('');

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
    try {
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
    } catch (e) {
      console.warn('Error playing audio chunk:', e);
    }
  }, []);

  // Request & configure microphone stream
  const enableMicrophone = useCallback(async (): Promise<boolean> => {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      setMicStatus('unsupported');
      setMicError('Microphone is not supported in this browser environment.');
      return false;
    }

    setMicStatus('requesting');
    setMicError(null);

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
      setMicStatus('granted');

      const inputCtx = new (window.AudioContext || (window as any).webkitAudioContext)({
        sampleRate: 16000,
      });
      inputCtxRef.current = inputCtx;

      const source = inputCtx.createMediaStreamSource(stream);
      const processor = inputCtx.createScriptProcessor(4096, 1, 1);
      scriptProcessorRef.current = processor;

      processor.onaudioprocess = (e) => {
        if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
          const inputData = e.inputBuffer.getChannelData(0);
          const base64PCM = floatTo16BitPCMBase64(inputData);
          wsRef.current.send(JSON.stringify({ audio: base64PCM }));
        }
      };

      source.connect(processor);
      processor.connect(inputCtx.destination);
      setIsListening(true);
      return true;
    } catch (err: any) {
      console.warn('Microphone permission or access issue:', err?.name || err?.message);
      if (err.name === 'NotAllowedError' || err.message?.includes('Permission denied')) {
        setMicStatus('denied');
        setMicError('Microphone permission is blocked. Tap "Allow Mic" or unblock in your browser address bar settings. You can also type below!');
      } else {
        setMicStatus('unsupported');
        setMicError('Microphone unavailable: ' + (err.message || 'Device error'));
      }
      setIsListening(false);
      return false;
    }
  }, []);

  const sendTextMessage = useCallback((text: string) => {
    if (!text.trim()) return;
    const cleanText = text.trim();

    setCurrentInputText(cleanText);
    setTranscriptHistory((prev) => [
      ...prev,
      { id: `in-${Date.now()}`, sender: 'user', text: cleanText },
    ]);

    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ text: cleanText }));
    } else {
      setConnectionError('Voice connection is not ready. Reconnecting...');
    }
  }, []);

  const startSession = useCallback(async () => {
    try {
      setConnectionError(null);

      // Extract auth token from cookie or URL params to avoid iframe 302 redirects
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const cookies = document.cookie.split(';').reduce((acc, c) => {
        const [k, v] = c.trim().split('=');
        if (k && v) acc[k] = decodeURIComponent(v);
        return acc;
      }, {} as Record<string, string>);
      const urlParams = new URLSearchParams(window.location.search);
      const authToken = cookies['___aistudio_auth_token'] || urlParams.get('___aistudio_auth_token');
      const wsUrl = `${protocol}//${window.location.host}/api/live-ws${authToken ? `?___aistudio_auth_token=${encodeURIComponent(authToken)}` : ''}`;

      if (wsRef.current) {
        wsRef.current.close();
      }

      const ws = new WebSocket(wsUrl);
      wsRef.current = ws;

      ws.onopen = async () => {
        setIsConnected(true);
        setConnectionError(null);
        // Automatically attempt microphone setup
        enableMicrophone();
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
            setConnectionError(msg.message);
          }
        } catch (e) {
          console.warn('Error handling WebSocket message:', e);
        }
      };

      ws.onclose = () => {
        setIsConnected(false);
        setIsListening(false);
        setIsSpeaking(false);
      };

      ws.onerror = (event: any) => {
        // Prevent printing raw Event object {"isTrusted": true}
        console.warn('Live voice WebSocket status update:', event?.type || 'error');
        setConnectionError('Voice connection interrupted. Tap to reconnect.');
        setIsConnected(false);
      };
    } catch (err: any) {
      setConnectionError(err.message || 'Failed to start Live Voice session');
    }
  }, [enableMicrophone, playAudioChunk, stopPlayback]);

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
      inputCtxRef.current.close().catch(() => {});
      inputCtxRef.current = null;
    }
    stopPlayback();
    setIsConnected(false);
    setIsListening(false);
    setIsSpeaking(false);
    setMicStatus('idle');
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
    micStatus,
    micError,
    connectionError,
    startSession,
    endSession,
    enableMicrophone,
    sendTextMessage,
    transcriptHistory,
    currentInputText,
    currentOutputText,
    error: micError || connectionError,
  };
}
