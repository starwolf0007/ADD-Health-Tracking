import React, { useEffect, useState } from 'react';
import {
  Mic,
  MicOff,
  PhoneOff,
  Sparkles,
  Volume2,
  Radio,
  AlertCircle,
  Send,
  RefreshCw,
  Lock,
} from 'lucide-react';
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
    micStatus,
    micError,
    connectionError,
    startSession,
    endSession,
    enableMicrophone,
    sendTextMessage,
    currentInputText,
    currentOutputText,
  } = useLiveVoice();

  const [typedMessage, setTypedMessage] = useState('');

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

  const handleSendText = (e: React.FormEvent) => {
    e.preventDefault();
    if (!typedMessage.trim()) return;
    sendTextMessage(typedMessage);
    setTypedMessage('');
  };

  return (
    <div className="fixed inset-0 z-50 bg-[#0C0C0D] flex flex-col justify-between p-4 sm:p-6 max-w-2xl mx-auto animate-in fade-in duration-300">
      {/* Top Bar */}
      <div className="flex items-center justify-between border-b border-[#232326] pb-3.5">
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

        <div className="flex items-center gap-2">
          <span className="text-[10px] font-medium px-2.5 py-0.5 rounded-full bg-[#BB86FC]/15 text-[#BB86FC] border border-[#BB86FC]/30 flex items-center gap-1">
            <Radio className="w-3 h-3" />
            {isConnected ? 'Live Audio · Ready' : 'Connecting…'}
          </span>
        </div>
      </div>

      {/* Center Visualizer & Avatar */}
      <div className="flex-1 flex flex-col items-center justify-center py-4 text-center">
        <div className="relative mb-5">
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
            <LexiAvatar size={92} visualState={isSpeaking ? 'thinking' : 'idle'} />
          </div>
        </div>

        {/* Live Status Indicator */}
        <div className="flex items-center gap-2 mb-3">
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
          ) : micStatus === 'denied' ? (
            <span className="text-xs font-medium text-[#D9A441] flex items-center gap-1.5">
              <MicOff className="w-4 h-4" />
              Microphone muted (Type to talk below)
            </span>
          ) : (
            <span className="text-xs text-[#8A8A8E]">Connecting to Live API…</span>
          )}
        </div>

        {/* Real-time Subtitles / Spoken Transcript */}
        <div className="w-full max-w-md bg-[#161618] border border-[#232326] rounded-2xl p-4 min-h-[100px] max-h-[140px] overflow-y-auto text-left shadow-inner flex flex-col justify-end">
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
              Speak naturally, or type below. Lexi responds out loud in real time.
            </p>
          )}
        </div>

        {/* Microphone Permission Help Banner */}
        {micStatus === 'denied' && (
          <div className="mt-3.5 p-3.5 bg-[#D9A441]/10 border border-[#D9A441]/30 rounded-2xl text-left max-w-md w-full space-y-2">
            <div className="flex items-start gap-2.5">
              <Lock className="w-4 h-4 text-[#D9A441] shrink-0 mt-0.5" />
              <div className="text-xs text-[#F0F0F0] leading-relaxed">
                <span className="font-semibold text-[#D9A441] block mb-0.5">
                  Microphone access is blocked
                </span>
                Click the lock icon in your browser's address bar to allow microphone access, or tap below to re-prompt.
              </div>
            </div>
            <button
              onClick={() => enableMicrophone()}
              className="w-full py-1.5 px-3 rounded-xl bg-[#D9A441]/20 hover:bg-[#D9A441]/30 text-[#D9A441] font-semibold text-xs transition-colors flex items-center justify-center gap-1.5"
            >
              <Mic className="w-3.5 h-3.5" />
              <span>Request Microphone Access</span>
            </button>
          </div>
        )}

        {/* Connection Error Banner */}
        {connectionError && (
          <div className="mt-3 p-3 bg-red-950/40 border border-red-800/40 rounded-xl text-xs text-red-300 flex items-center justify-between gap-2 max-w-md w-full">
            <div className="flex items-center gap-2">
              <AlertCircle className="w-4 h-4 shrink-0 text-red-400" />
              <span className="text-left">{connectionError}</span>
            </div>
            <button
              onClick={() => startSession()}
              className="px-2.5 py-1 rounded-lg bg-red-800/40 hover:bg-red-800/60 text-xs font-semibold text-red-200 shrink-0 flex items-center gap-1"
            >
              <RefreshCw className="w-3 h-3" />
              <span>Retry</span>
            </button>
          </div>
        )}
      </div>

      {/* Bottom Controls & Type-to-Talk Fallback */}
      <div className="space-y-3 pt-3 border-t border-[#232326]">
        {/* Quick Type-to-Talk input bar (works seamlessly even when mic is disabled/blocked) */}
        <form onSubmit={handleSendText} className="flex items-center gap-2 max-w-md mx-auto w-full">
          <input
            type="text"
            value={typedMessage}
            onChange={(e) => setTypedMessage(e.target.value)}
            placeholder="Type to talk with Lexi..."
            className="flex-1 bg-[#161618] border border-[#232326] focus:border-[#BB86FC] text-[#F0F0F0] placeholder-[#555559] text-xs px-3.5 py-2.5 rounded-xl outline-none transition-colors"
          />
          <button
            type="submit"
            disabled={!typedMessage.trim()}
            className="p-2.5 bg-[#BB86FC] hover:bg-[#BB86FC]/90 disabled:opacity-40 disabled:hover:bg-[#BB86FC] text-[#0C0C0D] rounded-xl transition-all active:scale-95 shrink-0"
            title="Send to Lexi"
            aria-label="Send message"
          >
            <Send className="w-4 h-4" />
          </button>
        </form>

        <div className="flex items-center justify-center gap-4">
          {micStatus === 'denied' || !isListening ? (
            <button
              onClick={() => enableMicrophone()}
              className="px-4 py-2 rounded-xl bg-[#2FB083]/15 hover:bg-[#2FB083]/25 text-[#2FB083] border border-[#2FB083]/30 text-xs font-semibold flex items-center gap-1.5 transition-colors"
              title="Turn on microphone"
            >
              <Mic className="w-4 h-4" />
              <span>Enable Mic</span>
            </button>
          ) : (
            <button
              onClick={() => {}}
              className="px-4 py-2 rounded-xl bg-[#2FB083]/20 text-[#2FB083] border border-[#2FB083]/40 text-xs font-semibold flex items-center gap-1.5"
              title="Microphone active"
            >
              <Mic className="w-4 h-4" />
              <span>Mic Active</span>
            </button>
          )}

          <button
            onClick={handleHangUp}
            className="py-2 px-5 rounded-xl bg-red-600 hover:bg-red-500 text-white font-semibold text-xs flex items-center gap-1.5 shadow-md shadow-red-600/30 active:scale-95 transition-all"
            title="End voice session"
          >
            <PhoneOff className="w-4 h-4" />
            <span>End Call</span>
          </button>
        </div>
      </div>
    </div>
  );
};

