import React, { useEffect } from 'react';
import { Award, X } from 'lucide-react';
import { Achievement } from '../types';

interface AchievementToastProps {
  achievement: Achievement | null;
  onDismiss: () => void;
}

export const AchievementToast: React.FC<AchievementToastProps> = ({
  achievement,
  onDismiss,
}) => {
  useEffect(() => {
    if (!achievement) return;
    const timer = setTimeout(() => {
      onDismiss();
    }, 4000);
    return () => clearTimeout(timer);
  }, [achievement, onDismiss]);

  if (!achievement) return null;

  return (
    <div className="fixed top-5 left-1/2 -translate-x-1/2 z-50 max-w-sm w-[92%] animate-in fade-in slide-in-from-top-4 duration-300">
      <div className="bg-[#1C1C1F] border border-[#FFD700]/30 shadow-xl shadow-black/40 rounded-2xl p-4 flex items-center gap-3 backdrop-blur-md">
        <div className="w-10 h-10 rounded-full bg-[#FFD700]/15 flex items-center justify-center shrink-0">
          <Award className="w-5 h-5 text-[#FFD700]" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-[11px] font-semibold tracking-wider text-[#FFD700] uppercase">
            {achievement.title}
          </p>
          <p className="text-xs text-[#F0F0F0] mt-0.5 leading-snug">
            {achievement.message}
          </p>
        </div>
        <button
          onClick={onDismiss}
          className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1 rounded-lg transition-colors"
          aria-label="Close"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
