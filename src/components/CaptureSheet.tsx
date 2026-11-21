import React, { useState, useRef, useEffect } from 'react';
import { X, Mic, Square, Loader2, ArrowRight } from 'lucide-react';
import { Task } from '../types';
import { taskStorage } from '../lib/storage';
import { useAudioTranscribe } from '../lib/useTranscribe';

interface CaptureSheetProps {
  isOpen: boolean;
  onClose: () => void;
  onCreated?: (task: Task) => void;
}

export const CaptureSheet: React.FC<CaptureSheetProps> = ({
  isOpen,
  onClose,
  onCreated,
}) => {
  const [text, setText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Audio transcription (voice capture)
  const { isRecording, isTranscribing, startRecording, stopAndTranscribe } =
    useAudioTranscribe();

  useEffect(() => {
    if (isOpen) {
      setText('');
      // Auto-focus immediately on open so no taps are wasted
      const timer = setTimeout(() => {
        inputRef.current?.focus();
      }, 50);
      return () => clearTimeout(timer);
    }
  }, [isOpen]);

  if (!isOpen) return null;

  const handleMicToggle = async () => {
    if (!isRecording) {
      await startRecording();
    } else {
      const transcript = await stopAndTranscribe();
      if (transcript) {
        setText((prev) => (prev ? `${prev} ${transcript}` : transcript));
      }
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    // Cmd+Enter or Enter without Shift immediately captures
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  };

  const handleSubmit = (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const cleanText = text.trim();
    if (!cleanText || submitting) return;

    setSubmitting(true);

    // Fast capture into inbox, verbatim wording kept, zero forms or required fields
    const newTask = taskStorage.captureItem(cleanText);

    if (onCreated) {
      onCreated(newTask);
    }

    setText('');
    setSubmitting(false);
    onClose();
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg bg-[#161618] border-t sm:border border-[#232326] rounded-t-3xl sm:rounded-3xl p-5 sm:p-6 shadow-2xl animate-in slide-in-from-bottom duration-200 max-h-[90vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Pull handle for mobile touch */}
        <div className="w-12 h-1 bg-[#2C2C30] rounded-full mx-auto mb-4 sm:hidden" />

        <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
          <div>
            <h3 className="text-base font-semibold text-[#F0F0F0]">Fast Capture</h3>
            <p className="text-xs text-[#8A8A8E]">Straight to inbox · Clarify later</p>
          </div>
          <button
            onClick={onClose}
            className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1.5 rounded-full hover:bg-[#232326] transition-colors"
            aria-label="Close"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="mt-4 flex-1 flex flex-col justify-between">
          <div className="relative">
            <textarea
              ref={inputRef}
              rows={3}
              value={text}
              onChange={(e) => setText(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="What's on your mind? Speak or type..."
              className="w-full bg-[#1C1C1F] text-base sm:text-lg text-[#F0F0F0] placeholder-[#555559] rounded-2xl p-4 pr-14 border border-[#2A2A2E] focus:border-[#2FB083] focus:ring-1 focus:ring-[#2FB083] outline-none resize-none transition-all"
            />

            {/* Audio Voice Dictation Button */}
            <button
              type="button"
              onClick={handleMicToggle}
              className={`absolute right-3 top-3 p-2.5 rounded-xl border transition-all ${
                isRecording
                  ? 'bg-red-600 text-white border-red-500 animate-pulse'
                  : 'bg-[#232326] text-[#8A8A8E] hover:text-[#2FB083] border-[#2E2E32]'
              }`}
              title={isRecording ? 'Stop listening' : 'Dictate by voice'}
              aria-label="Voice input"
            >
              {isRecording ? (
                <Square className="w-4 h-4" />
              ) : isTranscribing ? (
                <Loader2 className="w-4 h-4 animate-spin text-[#2FB083]" />
              ) : (
                <Mic className="w-4 h-4" />
              )}
            </button>
          </div>

          {(isRecording || isTranscribing) && (
            <div className="mt-2 p-2.5 rounded-xl bg-[#2FB083]/15 text-xs text-[#2FB083] flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-red-500 animate-ping" />
              <span>{isRecording ? 'Listening… tap mic to finish' : 'Transcribing voice…'}</span>
            </div>
          )}

          <div className="mt-6 flex items-center justify-between pt-3 border-t border-[#232326]">
            <span className="text-[11px] text-[#555559] hidden sm:inline">
              Press Enter to save
            </span>
            <div className="flex items-center gap-2 w-full sm:w-auto justify-end">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2.5 text-xs text-[#8A8A8E] hover:text-[#F0F0F0] font-medium"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={!text.trim() || submitting}
                className="flex-1 sm:flex-initial flex items-center justify-center gap-1.5 px-6 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 active:scale-98 text-[#0C0C0D] rounded-xl text-sm font-semibold disabled:opacity-40 transition-all shadow-md shadow-[#2FB083]/20"
              >
                <span>{submitting ? 'Saving…' : 'Capture to Inbox'}</span>
                <ArrowRight className="w-4 h-4" />
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
};
