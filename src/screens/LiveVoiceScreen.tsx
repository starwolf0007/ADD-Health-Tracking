import React, { useEffect } from 'react';
import { Mic, MicOff, PhoneOff, Sparkles, Volume2, Radio, AlertCircle } from 'lucide-react';
import { useLiveVoice } from '../lib/useLiveVoice';
import { LexiAvatar } from '../components/LexiAvatar';

interface LiveVoiceScreenProps {
  onClose: () => void;
}

export const LiveVoiceScreen: React.FC<LiveVoiceScreenProps> = ({ onClose }) => {
  const {
    isConnected,
    isSpeaking,
    isListening,
    startSession,
    endSession,
    transcriptHistory,
    currentInputText,
    currentOutputText,
    error,
  } = useLiveVoice();

  useEffect(() => {
    startSession();
    return () => {
      endSession();
    };
  }, []);

  const handleHangUp = () => {
    endSession();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 bg-[#0C0C0D] flex flex-col justify-between p-6 max-w-2xl mx-auto animate-in fade-in duration-300">
      {/* Top Bar */}
      <div className="flex items-center justify-between border-b border-[#232326] pb-4">
        <div className="flex items-center gap-2.5">
          <div
            className={`w-3 h-3 rounded-full ${
              isConnected ? 'bg-[#2FB083] animate-pulse' : 'bg-[#D9A441]'
            }`}
          />
          <div>
            <h3 className="text-sm font-medium text-[#F0F0F0]">Lexi Live Voice</h3>
            <p className="text-[11px] text-[#8A8A8E]">Real-time conversational companion</p>
          </div>
        </div>

        <span className="text-[10px] font-mono uppercase px-2 py-0.5 rounded-full bg-[#BB86FC]/15 text-[#BB86FC] border border-[#BB86FC]/30 flex items-center gap-1">
          <Radio className="w-3 h-3" />
          gemini-3.8-live
        </span>
      </div>

      {/* Center Visualizer & Avatar */}
      <div className="flex-1 flex flex-col items-center justify-center py-6 text-center">
        <div className="relative mb-6">
          {/* Animated glow rings when Lexi is speaking */}
          {isSpeaking && (
            <>
              <div className="absolute inset-0 rounded-full bg-[#BB86FC]/20 animate-ping" />
              <div className="absolute -inset-4 rounded-full bg-[#2FB083]/15 animate-pulse" />
            </>
          )}

          <div
            className={`relative p-2 rounded-full border-2 transition-all duration-300 ${
              isSpeaking
                ? 'border-[#BB86FC] scale-110 shadow-lg shadow-[#BB86FC]/25'
                : isListening
                ? 'border-[#2FB083] shadow-md shadow-[#2FB083]/20'
                : 'border-[#232326]'
            }`}
          >
            <LexiAvatar size={96} visualState={isSpeaking ? 'thinking' : 'idle'} />
          </div>
        </div>

        {/* Live Status Indicator */}
        <div className="flex items-center gap-2 mb-4">
          {isSpeaking ? (
            <span className="text-xs font-medium text-[#BB86FC] flex items-center gap-1.5 animate-pulse">
              <Volume2 className="w-4 h-4" />
              Lexi is speaking…
            </span>
          ) : isListening ? (
            <span className="text-xs font-medium text-[#2FB083] flex items-center gap-1.5">
              <Mic className="w-4 h-4" />
              Listening to you…
            </span>
          ) : (
            <span className="text-xs text-[#8A8A8E]">Connecting to Live API…</span>
          )}
        </div>

        {/* Real-time Subtitles / Spoken Transcript */}
        <div className="w-full max-w-md bg-[#161618] border border-[#232326] rounded-2xl p-4 min-h-[110px] max-h-[160px] overflow-y-auto text-left shadow-inner flex flex-col justify-end">
          {currentOutputText ? (
            <p className="text-sm text-[#F0F0F0] leading-relaxed">
              <span className="text-[11px] font-semibold text-[#BB86FC] uppercase mr-2">
                Lexi:
              </span>
              {currentOutputText}
            </p>
          ) : currentInputText ? (
            <p className="text-sm text-[#2FB083] leading-relaxed">
              <span className="text-[11px] font-semibold uppercase mr-2">You:</span>
              {currentInputText}
            </p>
          ) : (
            <p className="text-xs text-[#555559] italic text-center my-auto">
              Speak naturally. Lexi answers back in real-time without typing.
            </p>
          )}
        </div>

        {error && (
          <div className="mt-4 p-3 bg-red-950/40 border border-red-800/40 rounded-xl text-xs text-red-300 flex items-center gap-2 max-w-md">
            <AlertCircle className="w-4 h-4 shrink-0 text-red-400" />
            <span className="text-left">{error}</span>
          </div>
        )}
      </div>

      {/* Bottom Controls */}
      <div className="flex items-center justify-center gap-6 pt-4 border-t border-[#232326]">
        <button
          onClick={handleHangUp}
          className="w-16 h-16 rounded-full bg-red-600 hover:bg-red-500 text-white flex items-center justify-center shadow-lg shadow-red-600/30 active:scale-95 transition-all"
          title="End conversation"
        >
          <PhoneOff className="w-6 h-6" />
        </button>
      </div>
    </div>
  );
};
