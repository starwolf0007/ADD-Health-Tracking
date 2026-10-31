import { cloudFetch, requireCloudConsent } from './cloudClient';
import { useState, useRef, useEffect } from 'react';

export function useAudioTranscribe() {
  const [isRecording, setIsRecording] = useState(false);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);

  const startRecording = async (): Promise<boolean> => {
    setError(null);
    try {
      requireCloudConsent();
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const mediaRecorder = new MediaRecorder(stream, {
        mimeType: MediaRecorder.isTypeSupported('audio/webm')
          ? 'audio/webm'
          : '',
      });
      mediaRecorderRef.current = mediaRecorder;
      chunksRef.current = [];

      mediaRecorder.ondataavailable = (event) => {
        if (event.data.size > 0) {
          chunksRef.current.push(event.data);
        }
      };

      mediaRecorder.start(250);
      setIsRecording(true);
      return true;
    } catch (err: any) {
      console.error('Failed to access microphone for recording:', err);
      setError('Microphone access denied: ' + err.message);
      return false;
    }
  };

  const stopAndTranscribe = async (): Promise<string | null> => {
    if (
      !mediaRecorderRef.current ||
      mediaRecorderRef.current.state === 'inactive'
    ) {
      return null;
    }

    return new Promise((resolve) => {
      const recorder = mediaRecorderRef.current!;

      recorder.onstop = async () => {
        setIsRecording(false);
        setIsTranscribing(true);

        try {
          // Stop media tracks
          recorder.stream.getTracks().forEach((track) => track.stop());

          const mimeType = recorder.mimeType || 'audio/webm';
          const blob = new Blob(chunksRef.current, { type: mimeType });

          // Convert blob to base64
          const reader = new FileReader();
          reader.onerror = () => {
            setError('Could not read recorded audio.');
            setIsTranscribing(false);
            resolve(null);
          };
          reader.readAsDataURL(blob);
          reader.onloadend = async () => {
            const base64Url = reader.result as string;
            const base64Data = base64Url.split(',')[1];

            try {
              const res = await cloudFetch('/api/gemini/transcribe', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                  audioData: base64Data,
                  mimeType,
                }),
              });

              if (!res.ok) {
                const errData = await res.json();
                throw new Error(errData.error || 'Transcription failed');
              }

              const data = await res.json();
              setIsTranscribing(false);
              resolve(data.transcript || '');
            } catch (apiErr: any) {
              console.error('Transcription API error:', apiErr);
              setError(apiErr.message);
              setIsTranscribing(false);
              resolve(null);
            }
          };
        } catch (err: any) {
          console.error('Error during recording post-processing:', err);
          setError(err.message);
          setIsTranscribing(false);
          resolve(null);
        }
      };

      recorder.stop();
    });
  };

  const cancelRecording = () => {
    if (mediaRecorderRef.current) mediaRecorderRef.current.onstop = null;
    if (
      mediaRecorderRef.current &&
      mediaRecorderRef.current.state !== 'inactive'
    ) {
      mediaRecorderRef.current.stream
        .getTracks()
        .forEach((track) => track.stop());
      mediaRecorderRef.current.stop();
    }
    chunksRef.current = [];
    setIsRecording(false);
    setIsTranscribing(false);
  };

  useEffect(
    () => () => {
      const recorder = mediaRecorderRef.current;
      if (recorder) {
        recorder.onstop = null;
        recorder.stream.getTracks().forEach((track) => track.stop());
      }
    },
    [],
  );

  return {
    isRecording,
    isTranscribing,
    error,
    startRecording,
    stopAndTranscribe,
    cancelRecording,
  };
}
