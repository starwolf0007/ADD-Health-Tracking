import React, { useState, useEffect } from 'react';
import { X, Plus, Trash2, Clock, CheckCircle2, Circle, ArrowRight, Sparkles } from 'lucide-react';
import { Task, MicroStepItem } from '../types';
import { taskStorage } from '../lib/storage';

interface ClarifyModalProps {
  task: Task | null;
  isOpen: boolean;
  onClose: () => void;
  onClarified?: (task: Task) => void;
  onClarifyAndPick?: (task: Task) => void;
}

export const ClarifyModal: React.FC<ClarifyModalProps> = ({
  task,
  isOpen,
  onClose,
  onClarified,
  onClarifyAndPick,
}) => {
  const [title, setTitle] = useState('');
  const [estimatedMinutes, setEstimatedMinutes] = useState<number | undefined>(15);
  const [microSteps, setMicroSteps] = useState<MicroStepItem[]>([]);
  const [newStepText, setNewStepText] = useState('');
  const [hasTime, setHasTime] = useState(false);
  const [timeStr, setTimeStr] = useState('10:00');
  const [notes, setNotes] = useState('');

  useEffect(() => {
    if (task && isOpen) {
      setTitle(task.title || task.originalWording || '');
      setEstimatedMinutes(task.estimatedMinutes || 15);
      setMicroSteps(task.microSteps ? [...task.microSteps] : []);
      setNotes(task.notes || '');
      if (task.dueDate) {
        setHasTime(true);
        const d = new Date(task.dueDate);
        const hh = String(d.getHours()).padStart(2, '0');
        const mm = String(d.getMinutes()).padStart(2, '0');
        setTimeStr(`${hh}:${mm}`);
      } else {
        setHasTime(false);
      }
    }
  }, [task, isOpen]);

  if (!isOpen || !task) return null;

  const handleAddStep = () => {
    const clean = newStepText.trim();
    if (!clean) return;
    const newStep: MicroStepItem = {
      id: `step-${Date.now()}-${Math.random().toString(36).substring(2, 5)}`,
      title: clean,
      completed: false,
    };
    setMicroSteps((prev) => [...prev, newStep]);
    setNewStepText('');
  };

  const handleToggleStep = (stepId: string) => {
    setMicroSteps((prev) =>
      prev.map((s) => (s.id === stepId ? { ...s, completed: !s.completed } : s))
    );
  };

  const handleRemoveStep = (stepId: string) => {
    setMicroSteps((prev) => prev.filter((s) => s.id !== stepId));
  };

  const buildUpdates = () => {
    let dueDate: string | undefined = task.dueDate;
    if (hasTime) {
      const [h, m] = timeStr.split(':').map(Number);
      const now = new Date();
      const target = new Date(now.getFullYear(), now.getMonth(), now.getDate(), h || 10, m || 0);
      dueDate = target.toISOString();
    } else {
      dueDate = undefined;
    }

    return {
      title: title.trim() || task.title,
      estimatedMinutes,
      microSteps,
      dueDate,
      notes: notes.trim() || undefined,
    };
  };

  const handleSaveClarified = () => {
    const updates = buildUpdates();
    const updated = taskStorage.clarifyTask(task.id, updates);
    if (updated && onClarified) {
      onClarified(updated);
    }
    onClose();
  };

  const handleSaveAndPick = () => {
    const updates = buildUpdates();
    taskStorage.clarifyTask(task.id, updates);
    const picked = taskStorage.pickTask(task.id);
    if (picked && onClarifyAndPick) {
      onClarifyAndPick(picked);
    }
    onClose();
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg bg-[#161618] border-t sm:border border-[#232326] rounded-t-3xl sm:rounded-3xl p-5 sm:p-6 shadow-2xl animate-in slide-in-from-bottom duration-200 max-h-[90vh] overflow-y-auto"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
          <div>
            <h3 className="text-base font-semibold text-[#F0F0F0]">Clarify Task</h3>
            <p className="text-xs text-[#8A8A8E]">Make it small and ready to start</p>
          </div>
          <button
            onClick={onClose}
            className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1.5 rounded-full hover:bg-[#232326] transition-colors"
            aria-label="Close"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Verbatim Capture Quote */}
        {task.originalWording && (
          <div className="mt-3.5 px-3 py-2 rounded-xl bg-[#1C1C1F] border border-[#232326] text-xs text-[#8A8A8E]">
            <span className="text-[#555559] font-medium mr-1.5">Captured:</span>
            <span className="text-[#D0D0D2] italic">"{task.originalWording}"</span>
          </div>
        )}

        <div className="mt-4 space-y-4">
          {/* Title */}
          <div>
            <label className="text-xs font-medium text-[#8A8A8E] block mb-1.5">
              Task Name / Goal
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="What will you do?"
              className="w-full bg-[#1C1C1F] text-[#F0F0F0] rounded-xl px-3.5 py-2.5 text-sm border border-[#2A2A2E] focus:border-[#2FB083] outline-none"
            />
          </div>

          {/* Duration Estimate */}
          <div>
            <label className="text-xs font-medium text-[#8A8A8E] block mb-1.5">
              Target Duration
            </label>
            <div className="grid grid-cols-4 gap-2">
              {[5, 15, 25, 45].map((mins) => (
                <button
                  key={mins}
                  type="button"
                  onClick={() => setEstimatedMinutes(mins)}
                  className={`py-2 rounded-xl text-xs font-medium border transition-all ${
                    estimatedMinutes === mins
                      ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                      : 'bg-[#1C1C1F] text-[#8A8A8E] border-[#232326] hover:text-[#F0F0F0]'
                  }`}
                >
                  {mins} mins
                </button>
              ))}
            </div>
          </div>

          {/* Micro-steps Breakdown */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-xs font-medium text-[#8A8A8E]">
                Micro-Steps (Physical next actions)
              </label>
              <span className="text-[11px] text-[#555559]">
                {microSteps.filter((s) => s.completed).length}/{microSteps.length} done
              </span>
            </div>

            {/* Steps list */}
            {microSteps.length > 0 && (
              <div className="space-y-1.5 mb-2.5">
                {microSteps.map((step) => (
                  <div
                    key={step.id}
                    className="flex items-center justify-between gap-2 p-2 rounded-xl bg-[#1C1C1F] border border-[#232326]"
                  >
                    <button
                      type="button"
                      onClick={() => handleToggleStep(step.id)}
                      className="flex items-center gap-2 text-left flex-1"
                    >
                      {step.completed ? (
                        <CheckCircle2 className="w-4 h-4 text-[#2FB083] shrink-0" />
                      ) : (
                        <Circle className="w-4 h-4 text-[#8A8A8E] shrink-0" />
                      )}
                      <span
                        className={`text-xs ${
                          step.completed ? 'line-through text-[#555559]' : 'text-[#F0F0F0]'
                        }`}
                      >
                        {step.title}
                      </span>
                    </button>
                    <button
                      type="button"
                      onClick={() => handleRemoveStep(step.id)}
                      className="text-[#555559] hover:text-red-400 p-1"
                      title="Remove step"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* Add step input */}
            <div className="flex items-center gap-2">
              <input
                type="text"
                value={newStepText}
                onChange={(e) => setNewStepText(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    handleAddStep();
                  }
                }}
                placeholder="Next physical action (e.g. open browser tab)..."
                className="flex-1 bg-[#1C1C1F] text-xs text-[#F0F0F0] placeholder-[#555559] rounded-xl px-3 py-2 border border-[#2A2A2E] focus:border-[#2FB083] outline-none"
              />
              <button
                type="button"
                onClick={handleAddStep}
                disabled={!newStepText.trim()}
                className="p-2 rounded-xl bg-[#232326] text-[#8A8A8E] hover:text-[#2FB083] hover:bg-[#2A2A2E] disabled:opacity-40 transition-colors"
                title="Add step"
              >
                <Plus className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* Optional Scheduled Time */}
          <div className="bg-[#1C1C1F] rounded-2xl p-3 border border-[#232326]">
            <div className="flex items-center justify-between">
              <span className="text-xs text-[#8A8A8E]">Schedule a target time?</span>
              <button
                type="button"
                onClick={() => setHasTime(!hasTime)}
                className={`text-xs px-2.5 py-1 rounded-lg border transition-colors ${
                  hasTime
                    ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/30'
                    : 'bg-[#212124] text-[#8A8A8E] border-[#232326]'
                }`}
              >
                {hasTime ? 'Scheduled' : 'Flexible'}
              </button>
            </div>
            {hasTime && (
              <div className="flex items-center gap-2 mt-2 pt-2 border-t border-[#232326]">
                <Clock className="w-4 h-4 text-[#D9A441]" />
                <label className="text-xs text-[#8A8A8E]">Target Time:</label>
                <input
                  type="time"
                  value={timeStr}
                  onChange={(e) => setTimeStr(e.target.value)}
                  className="bg-[#212124] text-[#F0F0F0] text-xs px-2.5 py-1 rounded-lg border border-[#2A2A2E] outline-none"
                />
              </div>
            )}
          </div>
        </div>

        {/* Action Buttons */}
        <div className="mt-6 pt-3 border-t border-[#232326] flex flex-col sm:flex-row items-center justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="w-full sm:w-auto px-4 py-2 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSaveClarified}
            className="w-full sm:w-auto px-4 py-2.5 rounded-xl border border-[#2FB083]/40 bg-[#2FB083]/10 text-[#2FB083] hover:bg-[#2FB083]/20 text-xs font-semibold transition-all"
          >
            Save as Clarified
          </button>
          <button
            type="button"
            onClick={handleSaveAndPick}
            className="w-full sm:w-auto flex items-center justify-center gap-1.5 px-5 py-2.5 rounded-xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] text-xs font-semibold transition-all shadow-md shadow-[#2FB083]/20"
          >
            <span>Clarify & Pick Next</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  );
};
