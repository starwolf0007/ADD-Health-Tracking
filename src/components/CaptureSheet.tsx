import React, { useState } from 'react';
import { X, Calendar, Clock, Battery, BatteryLow, BatteryMedium, Mic, Square, Loader2 } from 'lucide-react';
import { EnergyLevel, Task } from '../types';
import { taskStorage } from '../lib/storage';
import { useAudioTranscribe } from '../lib/useTranscribe';

interface CaptureSheetProps {
  isOpen: boolean;
  onClose: () => void;
  scheduledDay?: Date;
  onCreated?: (task: Task) => void;
}

export const CaptureSheet: React.FC<CaptureSheetProps> = ({
  isOpen,
  onClose,
  scheduledDay,
  onCreated,
}) => {
  const [title, setTitle] = useState('');
  const [energy, setEnergy] = useState<EnergyLevel>('medium');
  const [hasTime, setHasTime] = useState(false);
  const [timeStr, setTimeStr] = useState('09:00');
  const [submitting, setSubmitting] = useState(false);

  // Voice transcription hook (gemini-3.5-transcribe)
  const { isRecording, isTranscribing, startRecording, stopAndTranscribe } =
    useAudioTranscribe();

  if (!isOpen) return null;

  const handleMicToggle = async () => {
    if (!isRecording) {
      await startRecording();
    } else {
      const transcript = await stopAndTranscribe();
      if (transcript) {
        setTitle((prev) => (prev ? `${prev} ${transcript}` : transcript));
      }
    }
  };

  const handleSubmit = (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    const cleanTitle = title.trim();
    if (!cleanTitle || submitting) return;

    setSubmitting(true);

    let dueDate: string | undefined = undefined;
    const baseDay = scheduledDay || new Date();

    if (hasTime || scheduledDay) {
      const [hours, minutes] = timeStr.split(':').map(Number);
      const targetDate = new Date(
        baseDay.getFullYear(),
        baseDay.getMonth(),
        baseDay.getDate(),
        hours || 9,
        minutes || 0
      );
      dueDate = targetDate.toISOString();
    }

    const newTask: Task = {
      id: `task-${Date.now()}-${Math.random().toString(36).substring(2, 6)}`,
      title: cleanTitle,
      energy,
      status: 'pending',
      createdAt: new Date().toISOString(),
      dueDate,
      estimatedMinutes: energy === 'low' ? 5 : energy === 'medium' ? 20 : 45,
      isQuickWin: energy === 'low',
    };

    taskStorage.save(newTask);
    if (onCreated) onCreated(newTask);

    setTitle('');
    setHasTime(false);
    setSubmitting(false);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
      <div
        className="w-full max-w-lg bg-[#161618] border-t sm:border border-[#232326] rounded-t-2xl sm:rounded-2xl p-5 shadow-2xl animate-in slide-in-from-bottom duration-250 max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Grab Handle */}
        <div className="w-10 h-1 bg-[#232326] rounded-full mx-auto mb-4 sm:hidden" />

        <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
          <h3 className="text-base font-medium text-[#F0F0F0]">
            {scheduledDay ? 'Schedule Task' : 'Quick Capture'}
          </h3>
          <button
            onClick={onClose}
            className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1 rounded-lg"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="mt-4 space-y-4">
          <div className="relative">
            <input
              type="text"
              autoFocus
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="What's on your mind? (or speak it)"
              className="w-full bg-transparent text-lg text-[#F0F0F0] placeholder-[#555559] border-none outline-none focus:ring-0 p-1 pr-12"
            />
            {/* Audio Voice Input Button */}
            <button
              type="button"
              onClick={handleMicToggle}
              className={`absolute right-1 top-1 p-2 rounded-xl border transition-colors ${
                isRecording
                  ? 'bg-red-600 text-white border-red-500 animate-pulse'
                  : 'bg-[#1C1C1F] text-[#8A8A8E] hover:text-[#2FB083] border-[#232326]'
              }`}
              title={isRecording ? 'Stop & transcribe' : 'Dictate with Gemini audio transcription'}
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
            <div className="p-2 rounded-lg bg-[#2FB083]/15 text-[11px] text-[#2FB083] flex items-center gap-2">
              <span className="w-2 h-2 rounded-full bg-red-500 animate-ping" />
              {isRecording ? 'Listening… tap to finish dictation' : 'Transcribing voice input…'}
            </div>
          )}

          {/* Scheduled Day / Time Selector */}
          <div className="bg-[#1C1C1F] rounded-xl p-3 border border-[#232326] space-y-2">
            <div className="flex items-center justify-between text-xs text-[#8A8A8E]">
              <div className="flex items-center gap-1.5">
                <Calendar className="w-3.5 h-3.5 text-[#2FB083]" />
                <span>
                  {scheduledDay
                    ? scheduledDay.toLocaleDateString(undefined, {
                        weekday: 'short',
                        month: 'short',
                        day: 'numeric',
                      })
                    : 'Adding to Today'}
                </span>
              </div>
              <button
                type="button"
                onClick={() => setHasTime(!hasTime)}
                className={`text-xs px-2.5 py-1 rounded-lg border transition-colors ${
                  hasTime
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/30'
                    : 'bg-[#212124] text-[#8A8A8E] border-[#232326]'
                }`}
              >
                {hasTime ? 'Has fixed time' : 'Flexible (No set time)'}
              </button>
            </div>

            {hasTime && (
              <div className="flex items-center gap-2 pt-2 border-t border-[#232326]">
                <Clock className="w-4 h-4 text-[#8A8A8E]" />
                <label className="text-xs text-[#8A8A8E]">Time:</label>
                <input
                  type="time"
                  value={timeStr}
                  onChange={(e) => setTimeStr(e.target.value)}
                  className="bg-[#212124] text-[#F0F0F0] text-sm px-2.5 py-1 rounded-lg border border-[#232326] outline-none"
                />
              </div>
            )}
          </div>

          {/* Energy Required */}
          <div>
            <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-2">
              Energy to Start
            </label>
            <div className="grid grid-cols-3 gap-2">
              <button
                type="button"
                onClick={() => setEnergy('low')}
                className={`flex items-center justify-center gap-2 p-2.5 rounded-xl border text-xs font-medium transition-all ${
                  energy === 'low'
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                    : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
                }`}
              >
                <BatteryLow className="w-4 h-4" />
                <span>Low</span>
              </button>

              <button
                type="button"
                onClick={() => setEnergy('medium')}
                className={`flex items-center justify-center gap-2 p-2.5 rounded-xl border text-xs font-medium transition-all ${
                  energy === 'medium'
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                    : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
                }`}
              >
                <BatteryMedium className="w-4 h-4" />
                <span>Medium</span>
              </button>

              <button
                type="button"
                onClick={() => setEnergy('high')}
                className={`flex items-center justify-center gap-2 p-2.5 rounded-xl border text-xs font-medium transition-all ${
                  energy === 'high'
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                    : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
                }`}
              >
                <Battery className="w-4 h-4" />
                <span>High</span>
              </button>
            </div>
          </div>

          {/* Actions */}
          <div className="pt-2 flex items-center justify-end gap-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2.5 text-xs text-[#8A8A8E] hover:text-[#F0F0F0] font-medium"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={!title.trim() || submitting}
              className="px-5 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold disabled:opacity-40 transition-colors"
            >
              {submitting ? 'Adding…' : 'Add to Today'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
