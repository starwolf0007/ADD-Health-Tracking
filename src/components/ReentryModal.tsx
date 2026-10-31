import React, { useState } from 'react';
import { X, CornerDownRight, PauseCircle } from 'lucide-react';
import { Task } from '../types';

interface ReentryModalProps {
  task: Task | null;
  isOpen: boolean;
  onClose: () => void;
  onConfirm: (lastStep: string, nextAction: string) => void;
}

export const ReentryModal: React.FC<ReentryModalProps> = ({
  task,
  isOpen,
  onClose,
  onConfirm,
}) => {
  const [lastStep, setLastStep] = useState(task?.reentryNote?.lastCompletedStep || '');
  const [nextAction, setNextAction] = useState(
    task?.reentryNote?.nextAction || 'Open the task and take the first physical step.'
  );

  if (!isOpen || !task) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onConfirm(lastStep.trim(), nextAction.trim());
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
      <div
        className="w-full max-w-md bg-[#161618] border border-[#232326] rounded-2xl p-5 shadow-2xl animate-in zoom-in-95 duration-200"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
          <div className="flex items-center gap-2">
            <PauseCircle className="w-5 h-5 text-[#D9A441]" />
            <h3 className="text-base font-medium text-[#F0F0F0]">Save Return Point</h3>
          </div>
          <button
            onClick={onClose}
            className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1 rounded-lg"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <p className="text-xs text-[#8A8A8E] mt-3 leading-relaxed">
          Switching contexts? Lower the friction of coming back by capturing where you left off
          and the very first physical action to resume.
        </p>

        <form onSubmit={handleSubmit} className="mt-4 space-y-3.5">
          <div>
            <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-1">
              Where did you stop?
            </label>
            <input
              type="text"
              value={lastStep}
              onChange={(e) => setLastStep(e.target.value)}
              placeholder="e.g. Gathered docs, drafted first paragraph..."
              className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3.5 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
            />
          </div>

          <div>
            <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-1">
              First physical step when you return
            </label>
            <div className="relative">
              <CornerDownRight className="w-4 h-4 text-[#2FB083] absolute left-3.5 top-3.5" />
              <input
                type="text"
                autoFocus
                value={nextAction}
                onChange={(e) => setNextAction(e.target.value)}
                placeholder="e.g. Click send email / open file..."
                className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm pl-10 pr-3.5 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
              />
            </div>
          </div>

          <div className="pt-3 flex items-center justify-end gap-2 border-t border-[#232326]">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
            >
              Cancel
            </button>
            <button
              type="submit"
              className="px-5 py-2.5 bg-[#D9A441] hover:bg-[#D9A441]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold"
            >
              Pause & Save Point
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
