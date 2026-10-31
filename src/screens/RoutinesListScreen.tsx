import React, { useState } from 'react';
import {
  Repeat,
  Plus,
  ChevronRight,
  Clock,
  ArrowUp,
  ArrowDown,
  X,
  Briefcase,
  Play,
} from 'lucide-react';
import { Routine, RoutineAnchor, RoutineStep } from '../types';
import { routineStorage } from '../lib/storage';

interface RoutinesListScreenProps {
  routines: Routine[];
  onLaunchRoutine: (routine: Routine) => void;
  refresh: () => void;
}

export const RoutinesListScreen: React.FC<RoutinesListScreenProps> = ({
  routines,
  onLaunchRoutine,
  refresh,
}) => {
  const [isAdding, setIsAdding] = useState(false);
  const [name, setName] = useState('');
  const [timeStr, setTimeStr] = useState('07:30');
  const [stepInput, setStepInput] = useState('');
  const [steps, setSteps] = useState<string[]>([]);
  const [anchor, setAnchor] = useState<RoutineAnchor>('morning');

  const handleAddStep = () => {
    const trimmed = stepInput.trim();
    if (!trimmed) return;
    setSteps([...steps, trimmed]);
    setStepInput('');
  };

  const handleRemoveStep = (idx: number) => {
    setSteps(steps.filter((_, i) => i !== idx));
  };

  const handleMoveStep = (idx: number, offset: number) => {
    const target = idx + offset;
    if (target < 0 || target >= steps.length) return;
    const copy = [...steps];
    const item = copy.splice(idx, 1)[0];
    copy.splice(target, 0, item);
    setSteps(copy);
  };

  const handleAddWorkPrepStarter = () => {
    const starter = [
      'Brush teeth',
      'Make bed',
      'Take medicine',
      'Grab wallet, watch, and keys',
      'Leave for work by 5:45 AM',
    ];
    setSteps((prev) => {
      const merged = [...prev];
      starter.forEach((s) => {
        if (!merged.includes(s)) merged.push(s);
      });
      return merged;
    });
  };

  const handleSaveRoutine = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanName = name.trim();
    if (!cleanName || steps.length === 0) {
      alert('Please provide a routine name and at least one step.');
      return;
    }

    const [h, m] = timeStr.split(':').map(Number);
    const routineId = `routine-${Date.now()}`;

    const newRoutine: Routine = {
      id: routineId,
      name: cleanName,
      anchor,
      scheduleHour: h || 7,
      scheduleMinute: m || 30,
      isActive: true,
      createdAt: new Date().toISOString(),
      steps: steps.map((s, index) => ({
        id: `step-${routineId}-${index}`,
        routineId,
        position: index,
        title: s,
        durationMinutes: 3,
        isComplete: false,
      })),
    };

    routineStorage.save(newRoutine);
    setName('');
    setSteps([]);
    setIsAdding(false);
    refresh();
  };

  const getTimeLabel = (r: Routine) => {
    if (r.scheduleHour !== undefined) {
      const h = r.scheduleHour % 12 === 0 ? 12 : r.scheduleHour % 12;
      const mm = String(r.scheduleMinute || 0).padStart(2, '0');
      const period = r.scheduleHour >= 12 ? 'PM' : 'AM';
      return `${h}:${mm} ${period}`;
    }
    switch (r.anchor) {
      case 'morning':
        return 'Morning';
      case 'midday':
        return 'Midday';
      case 'evening':
        return 'Evening';
      default:
        return 'Scheduled';
    }
  };

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-4">
      <div className="flex items-center justify-between pb-2 border-b border-[#232326]">
        <div>
          <h2 className="text-lg font-semibold text-[#F0F0F0]">Routines</h2>
          <p className="text-xs text-[#8A8A8E]">
            Ordered timed steps and habit stacks. Run one step at a time.
          </p>
        </div>
        <button
          onClick={() => setIsAdding(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold transition-colors"
        >
          <Plus className="w-4 h-4" />
          <span>Add Routine</span>
        </button>
      </div>

      {routines.length === 0 ? (
        <div className="text-center py-16 px-4 bg-[#161618] border border-dashed border-[#232326] rounded-2xl">
          <Repeat className="w-10 h-10 text-[#555559] mx-auto mb-3" />
          <h3 className="text-sm font-medium text-[#F0F0F0] mb-1">No routines yet</h3>
          <p className="text-xs text-[#8A8A8E] max-w-xs mx-auto leading-relaxed">
            Create a gentle step-by-step sequence for morning launch, evening shutdown, or work-prep.
          </p>
          <button
            onClick={() => setIsAdding(true)}
            className="mt-4 px-4 py-2 bg-[#212124] text-[#2FB083] text-xs font-medium rounded-xl border border-[#232326]"
          >
            Create Routine
          </button>
        </div>
      ) : (
        <div className="space-y-3">
          {routines.map((routine) => {
            const completedCount = routine.steps.filter((s) => s.isComplete).length;
            const totalCount = routine.steps.length;
            const isAllDone = totalCount > 0 && completedCount === totalCount;

            return (
              <div
                key={routine.id}
                onClick={() => onLaunchRoutine(routine)}
                className="p-4 bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] rounded-2xl cursor-pointer transition-all flex items-center justify-between gap-4 group shadow-sm"
              >
                <div className="space-y-1 min-w-0 flex-1">
                  <h3
                    className={`text-sm font-medium ${
                      isAllDone ? 'line-through text-[#8A8A8E]' : 'text-[#F0F0F0]'
                    }`}
                  >
                    {routine.name}
                  </h3>
                  <div className="flex items-center gap-2 text-xs text-[#8A8A8E]">
                    <Clock className="w-3.5 h-3.5 text-[#555559]" />
                    <span>{getTimeLabel(routine)}</span>
                    <span>·</span>
                    <span>{totalCount} steps</span>
                  </div>
                </div>

                <div className="flex items-center gap-3 shrink-0">
                  <span className="text-xs font-mono text-[#8A8A8E]">
                    {completedCount}/{totalCount}
                  </span>
                  <div className="p-2 rounded-xl bg-[#212124] group-hover:bg-[#2FB083]/20 text-[#8A8A8E] group-hover:text-[#2FB083] transition-colors">
                    <Play className="w-4 h-4 fill-current" />
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Add Routine Modal Sheet */}
      {isAdding && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
          <div
            className="w-full max-w-lg bg-[#161618] border-t sm:border border-[#232326] rounded-t-2xl sm:rounded-2xl p-5 shadow-2xl animate-in slide-in-from-bottom duration-250 max-h-[90vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
              <h3 className="text-base font-medium text-[#F0F0F0]">New Routine</h3>
              <button
                onClick={() => setIsAdding(false)}
                className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            <form onSubmit={handleSaveRoutine} className="mt-4 space-y-4">
              <div>
                <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-1">
                  Routine Name
                </label>
                <input
                  type="text"
                  autoFocus
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="e.g. Morning launch pad"
                  className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3.5 py-2.5 rounded-xl border border-[#232326] focus:border-[#2FB083] outline-none"
                />
              </div>

              {/* Time and Anchor */}
              <div className="grid grid-cols-2 gap-2">
                <div>
                  <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-1">
                    Scheduled Time
                  </label>
                  <input
                    type="time"
                    value={timeStr}
                    onChange={(e) => setTimeStr(e.target.value)}
                    className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3.5 py-2 rounded-xl border border-[#232326] outline-none"
                  />
                </div>
                <div>
                  <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase block mb-1">
                    Day Anchor
                  </label>
                  <select
                    value={anchor}
                    onChange={(e) => setAnchor(e.target.value as RoutineAnchor)}
                    className="w-full bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3.5 py-2 rounded-xl border border-[#232326] outline-none"
                  >
                    <option value="morning">Morning (~7 AM)</option>
                    <option value="midday">Midday (~12 PM)</option>
                    <option value="evening">Evening (~8 PM)</option>
                    <option value="custom">Custom Time</option>
                  </select>
                </div>
              </div>

              {/* Step Checklist */}
              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-[11px] font-semibold tracking-wider text-[#555559] uppercase">
                    Checklist Steps
                  </label>
                  <button
                    type="button"
                    onClick={handleAddWorkPrepStarter}
                    className="text-[11px] text-[#2FB083] hover:underline flex items-center gap-1"
                  >
                    <Briefcase className="w-3 h-3" />
                    <span>Use work-prep starter</span>
                  </button>
                </div>

                <div className="flex items-center gap-2 mb-2">
                  <input
                    type="text"
                    value={stepInput}
                    onChange={(e) => setStepInput(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') {
                        e.preventDefault();
                        handleAddStep();
                      }
                    }}
                    placeholder="Add a step (e.g. Brush teeth)"
                    className="flex-1 bg-[#1C1C1F] text-[#F0F0F0] text-sm px-3 py-2 rounded-xl border border-[#232326] outline-none"
                  />
                  <button
                    type="button"
                    onClick={handleAddStep}
                    className="p-2 bg-[#212124] hover:bg-[#28282C] text-[#2FB083] rounded-xl border border-[#232326]"
                  >
                    <Plus className="w-4 h-4" />
                  </button>
                </div>

                {steps.length > 0 && (
                  <div className="space-y-1.5 max-h-44 overflow-y-auto border border-[#232326] rounded-xl p-2 bg-[#1C1C1F]">
                    {steps.map((step, idx) => (
                      <div
                        key={idx}
                        className="flex items-center justify-between p-2 rounded-lg bg-[#161618] text-xs text-[#F0F0F0]"
                      >
                        <div className="flex items-center gap-2 min-w-0 flex-1">
                          <span className="text-[#555559] font-mono w-4">{idx + 1}</span>
                          <span className="truncate">{step}</span>
                        </div>
                        <div className="flex items-center gap-1 text-[#8A8A8E]">
                          <button
                            type="button"
                            disabled={idx === 0}
                            onClick={() => handleMoveStep(idx, -1)}
                            className="p-1 disabled:opacity-20 hover:text-[#F0F0F0]"
                          >
                            <ArrowUp className="w-3 h-3" />
                          </button>
                          <button
                            type="button"
                            disabled={idx === steps.length - 1}
                            onClick={() => handleMoveStep(idx, 1)}
                            className="p-1 disabled:opacity-20 hover:text-[#F0F0F0]"
                          >
                            <ArrowDown className="w-3 h-3" />
                          </button>
                          <button
                            type="button"
                            onClick={() => handleRemoveStep(idx)}
                            className="p-1 hover:text-[#D9A441]"
                          >
                            <X className="w-3 h-3" />
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>

              <div className="pt-2 flex items-center justify-end gap-2 border-t border-[#232326]">
                <button
                  type="button"
                  onClick={() => setIsAdding(false)}
                  className="px-4 py-2 text-xs text-[#8A8A8E]"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={!name.trim() || steps.length === 0}
                  className="px-5 py-2.5 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold disabled:opacity-40"
                >
                  Save Routine
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
};
