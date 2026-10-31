import React, { useState } from 'react';
import { Flower2, Clock, Check, MessageSquare, X } from 'lucide-react';
import { MoodLevel, MoodLog } from '../types';
import { moodStorage } from '../lib/storage';
import { MOOD_META } from '../lib/executive';

interface ReflectScreenProps {
  todayMood: MoodLog | null;
  recentMoods: MoodLog[];
  refresh: () => void;
}

export const ReflectScreen: React.FC<ReflectScreenProps> = ({
  todayMood,
  recentMoods,
  refresh,
}) => {
  const [isNoteOpen, setIsNoteOpen] = useState(false);
  const [selectedLevel, setSelectedLevel] = useState<MoodLevel | null>(null);
  const [noteText, setNoteText] = useState('');
  const [feedbackToast, setFeedbackToast] = useState<string | null>(null);

  const handleSelectMood = (level: MoodLevel) => {
    setSelectedLevel(level);
    setIsNoteOpen(true);
  };

  const handleSaveCheckIn = (skipNote = false) => {
    if (!selectedLevel) return;
    const note = skipNote ? undefined : noteText.trim() || undefined;

    moodStorage.log(selectedLevel, note);
    const triggers = MOOD_META[selectedLevel].triggersQuickWins;
    const label = MOOD_META[selectedLevel].label;

    const message = triggers
      ? `Logged ${label}. Today will lean toward Quick Wins.`
      : `Logged ${label}.`;

    setFeedbackToast(message);
    setTimeout(() => setFeedbackToast(null), 3500);

    setNoteText('');
    setSelectedLevel(null);
    setIsNoteOpen(false);
    refresh();
  };

  const formatTime = (iso: string) => {
    const d = new Date(iso);
    return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  };

  const formatDay = (iso: string) => {
    const now = new Date();
    const d = new Date(iso);
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    const diffDays = Math.round((today.getTime() - day.getTime()) / 86400000);

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Yesterday';
    if (diffDays < 7) return `${diffDays} days ago`;
    return d.toLocaleDateString();
  };

  const levels: MoodLevel[] = ['veryLow', 'low', 'neutral', 'good', 'great'];

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-6">
      {/* Toast */}
      {feedbackToast && (
        <div className="p-3 rounded-xl bg-[#2FB083]/15 border border-[#2FB083]/30 text-xs text-[#2FB083] font-medium animate-in fade-in slide-in-from-top-2">
          {feedbackToast}
        </div>
      )}

      <div>
        <h2 className="text-lg font-semibold text-[#F0F0F0]">Reflect</h2>
        <p className="text-xs text-[#8A8A8E] mt-0.5">
          A calm mood check-in. Sensitive data is kept strictly on-device.
        </p>
      </div>

      {/* Main Prompt */}
      <div className="space-y-2">
        <h3 className="text-base font-normal text-[#F0F0F0]">
          How are you right now?
        </h3>
        <p className="text-xs text-[#8A8A8E] leading-relaxed">
          A rough or low check-in gently shifts Today toward Quick Wins. No scores shown — just a calm signal.
        </p>
      </div>

      {/* Today's Existing Log (if already logged today) */}
      {todayMood && (
        <div className="p-4 rounded-2xl bg-[#161618] border border-[#232326] space-y-1 shadow-sm">
          <div className="flex items-center justify-between">
            <span className="text-sm font-medium text-[#F0F0F0]">
              Today: {MOOD_META[todayMood.level].label}
            </span>
            <span className="text-xs text-[#555559] font-mono">
              {formatTime(todayMood.loggedAt)}
            </span>
          </div>
          {todayMood.note && (
            <p className="text-xs text-[#8A8A8E] italic pt-1">
              "{todayMood.note}"
            </p>
          )}
          {MOOD_META[todayMood.level].triggersQuickWins && (
            <div className="pt-2">
              <span className="text-[10px] font-semibold tracking-wider uppercase px-2 py-0.5 rounded bg-[#2FB083]/15 text-[#2FB083]">
                Quick Wins Active
              </span>
            </div>
          )}
        </div>
      )}

      {/* Mood Chips (5-point calm check-in) */}
      <div className="space-y-2">
        {todayMood && (
          <span className="text-[11px] text-[#555559] block">
            Log another if things shifted:
          </span>
        )}
        <div className="grid grid-cols-5 gap-2">
          {levels.map((lvl) => {
            const meta = MOOD_META[lvl];
            const isSelected = todayMood?.level === lvl;

            return (
              <button
                key={lvl}
                onClick={() => handleSelectMood(lvl)}
                className={`py-3.5 px-2 rounded-xl border text-center transition-all ${
                  isSelected
                    ? 'bg-[#2FB083]/15 border-[#2FB083]/40 text-[#2FB083] font-semibold'
                    : 'bg-[#1C1C1F] border-[#232326] text-[#F0F0F0] hover:border-[#2FB083]/30'
                }`}
              >
                <span className="text-xs block">{meta.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Recent History */}
      <div className="space-y-3 pt-4 border-t border-[#232326]">
        <span className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block">
          Recent Check-ins
        </span>

        {recentMoods.length === 0 ? (
          <p className="text-xs text-[#555559]">
            No check-ins yet. The first one is enough.
          </p>
        ) : (
          <div className="space-y-2">
            {recentMoods.map((log) => (
              <div
                key={log.id}
                className="p-3.5 rounded-xl bg-[#161618] border border-[#232326] flex items-center justify-between"
              >
                <div>
                  <span className="text-xs font-medium text-[#F0F0F0] block">
                    {MOOD_META[log.level].label}
                  </span>
                  {log.note && (
                    <span className="text-xs text-[#8A8A8E] block mt-0.5">
                      {log.note}
                    </span>
                  )}
                </div>
                <div className="text-right">
                  <span className="text-xs text-[#555559] block">
                    {formatDay(log.loggedAt)}
                  </span>
                  <span className="text-[10px] text-[#3C3C40] block font-mono">
                    {formatTime(log.loggedAt)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Optional Note Modal */}
      {isNoteOpen && selectedLevel && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div
            className="w-full max-w-md bg-[#161618] border-t sm:border border-[#232326] rounded-t-2xl sm:rounded-2xl p-5 shadow-2xl animate-in slide-in-from-bottom duration-250"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
              <h3 className="text-base font-medium text-[#F0F0F0]">
                Anything to note? (Optional)
              </h3>
              <button
                onClick={() => setIsNoteOpen(false)}
                className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="mt-4 space-y-4">
              <p className="text-xs text-[#8A8A8E]">
                Checking in as{' '}
                <span className="text-[#2FB083] font-semibold">
                  {MOOD_META[selectedLevel].label}
                </span>
                . Add any helpful thought, or tap Skip.
              </p>

              <textarea
                autoFocus
                rows={3}
                value={noteText}
                onChange={(e) => setNoteText(e.target.value)}
                placeholder="Optional context (sleep, energy, context shift)..."
                className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm p-3.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none resize-none"
              />

              <div className="flex items-center justify-between pt-2">
                <button
                  type="button"
                  onClick={() => handleSaveCheckIn(true)}
                  className="px-4 py-2 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
                >
                  Skip
                </button>
                <button
                  type="button"
                  onClick={() => handleSaveCheckIn(false)}
                  className="px-5 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold"
                >
                  Save Check-in
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
