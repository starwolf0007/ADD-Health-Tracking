import React, { useState, useEffect } from 'react';
import {
  Play,
  Pause,
  CheckCircle2,
  Circle,
  Clock,
  Sparkles,
  ArrowRight,
  RotateCcw,
  Plus,
  Inbox,
  Edit3,
  X,
} from 'lucide-react';
import { Task, MicroStepItem } from '../types';
import { taskStorage, getElapsedActiveSeconds } from '../lib/storage';
import { ClarifyModal } from '../components/ClarifyModal';

interface TodayScreenProps {
  tasks: Task[];
  onOpenRecall: () => void;
  onOpenCapture: () => void;
  refresh: () => void;
}

function formatCountUp(seconds: number): string {
  const s = Math.max(0, Math.floor(seconds));
  const hrs = Math.floor(s / 3600);
  const mins = Math.floor((s % 3600) / 60);
  const remainingSecs = s % 60;

  const mm = String(mins).padStart(2, '0');
  const ss = String(remainingSecs).padStart(2, '0');

  if (hrs > 0) {
    const hh = String(hrs).padStart(2, '0');
    return `${hh}:${mm}:${ss}`;
  }
  return `${mm}:${ss}`;
}

function getCalmTimeUntil(dueDateIso?: string): string | null {
  if (!dueDateIso) return null;
  const target = new Date(dueDateIso).getTime();
  if (isNaN(target)) return null;

  const diffMs = target - Date.now();
  const diffMinutes = Math.round(diffMs / 60000);

  if (diffMinutes > 60) {
    const hours = Math.round(diffMinutes / 60);
    return `in about ${hours} hour${hours > 1 ? 's' : ''}`;
  }
  if (diffMinutes > 1) {
    return `in ${diffMinutes} minutes`;
  }
  if (diffMinutes >= 0) {
    return 'starting now';
  }
  const overdueMins = Math.abs(diffMinutes);
  if (overdueMins < 60) {
    return `${overdueMins}m ago`;
  }
  return 'scheduled today';
}

export const TodayScreen: React.FC<TodayScreenProps> = ({
  tasks,
  onOpenRecall,
  onOpenCapture,
  refresh,
}) => {
  // Live UI re-render tick every second (display only, does NOT mutate state or storage)
  const [, setTick] = useState(0);
  const [clarifyingTask, setClarifyingTask] = useState<Task | null>(null);
  const [lexiDismissedTaskId, setLexiDismissedTaskId] = useState<string | null>(null);

  // Identify the single task for the Now card:
  // Priority: active/resumed -> paused -> picked
  const activeTask = tasks.find((t) => t.status === 'active' || t.status === 'resumed');
  const pausedTask = !activeTask ? tasks.find((t) => t.status === 'paused') : null;
  const pickedTask = !activeTask && !pausedTask ? tasks.find((t) => t.status === 'picked') : null;
  const currentTask = activeTask || pausedTask || pickedTask || null;

  const isTimerRunning = Boolean(
    currentTask && (currentTask.status === 'active' || currentTask.status === 'resumed')
  );

  useEffect(() => {
    if (!isTimerRunning) return;
    const interval = setInterval(() => {
      setTick((prev) => (prev + 1) % 1000000);
    }, 1000);
    return () => clearInterval(interval);
  }, [isTimerRunning]);

  // Actions on Current Task
  const handleStart = (taskId: string) => {
    taskStorage.startTask(taskId);
    refresh();
  };

  const handlePause = (taskId: string) => {
    taskStorage.pauseTask(taskId);
    refresh();
  };

  const handleResume = (taskId: string) => {
    taskStorage.resumeTask(taskId);
    refresh();
  };

  const handleFinish = (taskId: string) => {
    taskStorage.finishTask(taskId);
    refresh();
  };

  const handleToggleMicroStep = (task: Task, stepId: string) => {
    if (!task.microSteps) return;
    const updated = task.microSteps.map((s) =>
      s.id === stepId
        ? {
            ...s,
            completed: !s.completed,
            completedAt: !s.completed ? new Date().toISOString() : undefined,
          }
        : s
    );
    taskStorage.updateMicroSteps(task.id, updated);
    refresh();
  };

  // Lexi Next-Up Nudge logic:
  // When next picked task is within ~15 minutes, propose starting it calmly
  const showLexiNudge =
    pickedTask &&
    pickedTask.id !== lexiDismissedTaskId &&
    pickedTask.dueDate &&
    (() => {
      const diffMs = new Date(pickedTask.dueDate).getTime() - Date.now();
      const diffMins = Math.round(diffMs / 60000);
      return diffMins >= 0 && diffMins <= 20;
    })();

  return (
    <div className="p-4 sm:p-6 pb-28 max-w-xl mx-auto w-full flex flex-col justify-center min-h-[75vh]">
      {/* Lexi Gentle Next-Up Nudge (Proposal only, zero write authority) */}
      {showLexiNudge && pickedTask && (
        <div className="mb-4 p-4 rounded-3xl bg-[#1C1826] border border-[#BB86FC]/30 text-xs text-[#F0F0F0] shadow-lg animate-in fade-in duration-300">
          <div className="flex items-start justify-between gap-2">
            <div className="flex items-center gap-2 text-[#BB86FC] font-medium">
              <Sparkles className="w-4 h-4 shrink-0" />
              <span>Lexi · Next up soon</span>
            </div>
            <button
              onClick={() => setLexiDismissedTaskId(pickedTask.id)}
              className="text-[#8A8A8E] hover:text-[#F0F0F0] p-1"
              aria-label="Dismiss nudge"
            >
              <X className="w-3.5 h-3.5" />
            </button>
          </div>
          <p className="mt-1.5 text-sm text-[#F0F0F0]/90">
            "{pickedTask.title}" is coming up {getCalmTimeUntil(pickedTask.dueDate)}.
          </p>
          <div className="mt-3 flex items-center justify-end gap-2">
            <button
              onClick={() => setLexiDismissedTaskId(pickedTask.id)}
              className="px-3 py-1.5 text-xs text-[#8A8A8E] hover:text-[#F0F0F0]"
            >
              Dismiss
            </button>
            <button
              onClick={() => handleStart(pickedTask.id)}
              className="px-3.5 py-1.5 bg-[#BB86FC] hover:bg-[#BB86FC]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold transition-all shadow-sm"
            >
              Start now
            </button>
          </div>
        </div>
      )}

      {/* STATE 1: NOTHING PICKED YET -> Calm invitation, not an error */}
      {!currentTask && (
        <div className="bg-[#161618] rounded-3xl p-6 sm:p-8 border border-[#232326] text-center shadow-xl">
          <div className="w-14 h-14 rounded-full bg-[#2FB083]/10 border border-[#2FB083]/20 flex items-center justify-center mx-auto mb-4 text-[#2FB083]">
            <Sparkles className="w-6 h-6 stroke-[1.8]" />
          </div>
          <h2 className="text-xl sm:text-2xl font-semibold text-[#F0F0F0] tracking-tight">
            Nothing picked right now
          </h2>
          <p className="text-sm text-[#8A8A8E] mt-2 max-w-sm mx-auto leading-relaxed">
            When you're ready, pick one win to focus on, or capture whatever thought is on your mind.
          </p>

          <div className="mt-6 flex flex-col sm:flex-row items-center justify-center gap-3">
            <button
              onClick={onOpenRecall}
              className="w-full sm:w-auto flex items-center justify-center gap-2 px-5 py-3 rounded-2xl bg-[#2FB083] hover:bg-[#2FB083]/90 active:scale-98 text-[#0C0C0D] text-sm font-semibold transition-all shadow-md shadow-[#2FB083]/20"
            >
              <Inbox className="w-4 h-4" />
              <span>Pick from Recall & Inbox</span>
            </button>
            <button
              onClick={onOpenCapture}
              className="w-full sm:w-auto flex items-center justify-center gap-2 px-5 py-3 rounded-2xl bg-[#212124] hover:bg-[#28282C] text-[#F0F0F0] text-sm font-medium transition-all border border-[#2A2A2E]"
            >
              <Plus className="w-4 h-4" />
              <span>Capture a Thought</span>
            </button>
          </div>
        </div>
      )}

      {/* STATE 2: PAUSED TASK -> The Re-Entry Card */}
      {currentTask && currentTask.status === 'paused' && (
        <div className="bg-[#161618] rounded-3xl p-6 sm:p-8 border border-[#D9A441]/40 shadow-2xl relative overflow-hidden">
          {/* Subtle top amber glow accent for paused return */}
          <div className="absolute top-0 left-0 right-0 h-1 bg-gradient-to-r from-[#D9A441] to-[#2FB083]" />

          <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
            <div className="flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-[#D9A441]" />
              <span className="text-xs font-semibold uppercase tracking-wider text-[#D9A441]">
                Re-Entry Card
              </span>
            </div>
            <span className="text-xs text-[#8A8A8E] flex items-center gap-1 font-mono">
              <Clock className="w-3.5 h-3.5 text-[#D9A441]" />
              <span>{formatCountUp(currentTask.accumulatedActiveSeconds || 0)} elapsed</span>
            </span>
          </div>

          <div className="mt-4">
            <h2 className="text-xl sm:text-2xl font-bold text-[#F0F0F0] tracking-tight break-words">
              {currentTask.title}
            </h2>
            {currentTask.originalWording && currentTask.originalWording !== currentTask.title && (
              <p className="text-xs text-[#8A8A8E] italic mt-1 break-words">
                "{currentTask.originalWording}"
              </p>
            )}
          </div>

          {/* Re-entry Progress: Real completed micro-steps first */}
          <div className="mt-5 p-4 rounded-2xl bg-[#1C1C1F] border border-[#232326] space-y-3">
            {/* Completed steps */}
            {(() => {
              const completed = currentTask.microSteps?.filter((s) => s.completed) || [];
              const pending = currentTask.microSteps?.filter((s) => !s.completed) || [];

              if (completed.length > 0) {
                return (
                  <div className="space-y-1.5">
                    <span className="text-[11px] font-semibold text-[#2FB083] uppercase tracking-wider block">
                      Already done:
                    </span>
                    {completed.map((s) => (
                      <div key={s.id} className="flex items-center gap-2 text-xs text-[#8A8A8E]">
                        <CheckCircle2 className="w-3.5 h-3.5 text-[#2FB083] shrink-0" />
                        <span className="line-through">{s.title}</span>
                      </div>
                    ))}
                  </div>
                );
              }

              return (
                <div className="text-xs text-[#8A8A8E]">
                  <span>No steps completed yet — pick up with the first step:</span>
                </div>
              );
            })()}

            {/* Next Unfinished Micro-step */}
            {(() => {
              const pending = currentTask.microSteps?.filter((s) => !s.completed) || [];
              const nextStep = pending[0];

              if (nextStep) {
                return (
                  <div className="pt-2 border-t border-[#232326]">
                    <span className="text-[11px] font-semibold text-[#D9A441] uppercase tracking-wider block mb-1">
                      Next physical step:
                    </span>
                    <div className="flex items-center gap-2 text-sm text-[#F0F0F0] font-medium bg-[#212124] p-2.5 rounded-xl border border-[#2A2A2E]">
                      <Circle className="w-4 h-4 text-[#D9A441] shrink-0" />
                      <span>{nextStep.title}</span>
                    </div>
                  </div>
                );
              }

              if (currentTask.reentryNote?.nextAction) {
                return (
                  <div className="pt-2 border-t border-[#232326]">
                    <span className="text-[11px] font-semibold text-[#D9A441] uppercase tracking-wider block mb-1">
                      Next physical step:
                    </span>
                    <div className="text-sm text-[#F0F0F0] font-medium bg-[#212124] p-2.5 rounded-xl border border-[#2A2A2E]">
                      {currentTask.reentryNote.nextAction}
                    </div>
                  </div>
                );
              }

              return null;
            })()}
          </div>

          {/* Action Row */}
          <div className="mt-6 flex flex-col sm:flex-row items-center justify-between gap-3 pt-3 border-t border-[#232326]">
            <button
              onClick={() => setClarifyingTask(currentTask)}
              className="w-full sm:w-auto px-4 py-2.5 rounded-xl text-xs text-[#8A8A8E] hover:text-[#F0F0F0] font-medium flex items-center justify-center gap-1.5"
            >
              <Edit3 className="w-3.5 h-3.5" />
              <span>Edit Steps</span>
            </button>

            <div className="flex items-center gap-2 w-full sm:w-auto">
              <button
                onClick={() => handleFinish(currentTask.id)}
                className="flex-1 sm:flex-initial px-4 py-3 rounded-2xl bg-[#212124] hover:bg-[#28282C] text-xs font-semibold text-[#F0F0F0] transition-colors border border-[#2A2A2E]"
              >
                Mark Finished
              </button>
              <button
                onClick={() => handleResume(currentTask.id)}
                className="flex-2 sm:flex-initial flex items-center justify-center gap-2 px-6 py-3 rounded-2xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] text-sm font-bold transition-all shadow-lg shadow-[#2FB083]/25 active:scale-98"
              >
                <Play className="w-4 h-4 fill-current" />
                <span>Resume</span>
              </button>
            </div>
          </div>
        </div>
      )}

      {/* STATE 3: PICKED TASK -> Time until + Emerald Start Action */}
      {currentTask && currentTask.status === 'picked' && (
        <div className="bg-[#161618] rounded-3xl p-6 sm:p-8 border border-[#232326] shadow-xl">
          <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
            <span className="text-xs font-semibold uppercase tracking-wider text-[#2FB083]">
              Up Next
            </span>
            {currentTask.dueDate && (
              <span className="text-xs font-medium text-[#D9A441] flex items-center gap-1">
                <Clock className="w-3.5 h-3.5 text-[#D9A441]" />
                <span>{getCalmTimeUntil(currentTask.dueDate)}</span>
              </span>
            )}
          </div>

          <div className="mt-4">
            <h2 className="text-xl sm:text-2xl font-bold text-[#F0F0F0] tracking-tight break-words">
              {currentTask.title}
            </h2>
            {currentTask.originalWording && currentTask.originalWording !== currentTask.title && (
              <p className="text-xs text-[#8A8A8E] italic mt-1 break-words">
                "{currentTask.originalWording}"
              </p>
            )}
          </div>

          {/* Micro-steps preview if clarified */}
          {currentTask.microSteps && currentTask.microSteps.length > 0 && (
            <div className="mt-4 p-3.5 rounded-2xl bg-[#1C1C1F] border border-[#232326] space-y-1.5">
              <span className="text-[11px] font-semibold text-[#8A8A8E] block mb-1">
                First physical steps:
              </span>
              {currentTask.microSteps.slice(0, 3).map((step) => (
                <div key={step.id} className="flex items-center gap-2 text-xs text-[#D0D0D2]">
                  <Circle className="w-3.5 h-3.5 text-[#8A8A8E] shrink-0" />
                  <span>{step.title}</span>
                </div>
              ))}
            </div>
          )}

          {/* Actions */}
          <div className="mt-6 flex flex-col sm:flex-row items-center justify-between gap-3 pt-3 border-t border-[#232326]">
            <div className="flex items-center gap-2 w-full sm:w-auto">
              <button
                onClick={() => setClarifyingTask(currentTask)}
                className="px-3.5 py-2.5 rounded-xl text-xs text-[#8A8A8E] hover:text-[#F0F0F0] font-medium flex items-center gap-1"
              >
                <Edit3 className="w-3.5 h-3.5" />
                <span>Clarify</span>
              </button>
              <button
                onClick={onOpenRecall}
                className="px-3.5 py-2.5 rounded-xl text-xs text-[#8A8A8E] hover:text-[#F0F0F0] font-medium"
              >
                Change picked
              </button>
            </div>

            <button
              onClick={() => handleStart(currentTask.id)}
              className="w-full sm:w-auto flex items-center justify-center gap-2 px-8 py-3 rounded-2xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] text-sm font-bold transition-all shadow-lg shadow-[#2FB083]/25 active:scale-98"
            >
              <Play className="w-4 h-4 fill-current" />
              <span>Start</span>
            </button>
          </div>
        </div>
      )}

      {/* STATE 4: ACTIVE OR RESUMED TASK -> Live count-up display + Pause & Park + Finish */}
      {currentTask && (currentTask.status === 'active' || currentTask.status === 'resumed') && (
        <div className="bg-[#161618] rounded-3xl p-6 sm:p-8 border border-[#2FB083]/40 shadow-2xl relative overflow-hidden">
          {/* Subtle emerald top glow */}
          <div className="absolute top-0 left-0 right-0 h-1 bg-[#2FB083]" />

          <div className="flex items-center justify-between pb-3 border-b border-[#232326]">
            <div className="flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-[#2FB083] animate-pulse" />
              <span className="text-xs font-semibold uppercase tracking-wider text-[#2FB083]">
                In Progress
              </span>
            </div>
            {currentTask.targetEndTime && (
              <span className="text-xs text-[#D9A441] flex items-center gap-1">
                <Clock className="w-3 h-3 text-[#D9A441]" />
                <span>Target {getCalmTimeUntil(currentTask.targetEndTime)}</span>
              </span>
            )}
          </div>

          <div className="mt-4">
            <h2 className="text-xl sm:text-2xl font-bold text-[#F0F0F0] tracking-tight break-words">
              {currentTask.title}
            </h2>
            {currentTask.originalWording && currentTask.originalWording !== currentTask.title && (
              <p className="text-xs text-[#8A8A8E] italic mt-1 break-words">
                "{currentTask.originalWording}"
              </p>
            )}
          </div>

          {/* Live Count-Up Timer Display (Derived from persisted timestamps) */}
          <div className="my-6 p-6 rounded-2xl bg-[#1C1C1F] border border-[#2A2A2E] text-center">
            <span className="text-[11px] font-semibold uppercase tracking-wider text-[#D9A441] block mb-1">
              Active Elapsed Time
            </span>
            <div className="text-4xl sm:text-5xl font-mono font-bold text-[#F0F0F0] tracking-tight">
              {formatCountUp(getElapsedActiveSeconds(currentTask))}
            </div>
            <span className="text-[11px] text-[#555559] mt-1 block">
              Count-up only · Zero pressure
            </span>
          </div>

          {/* Micro-steps checklist */}
          {currentTask.microSteps && currentTask.microSteps.length > 0 && (
            <div className="mb-6 space-y-2">
              <span className="text-xs font-medium text-[#8A8A8E] block">Micro-Steps:</span>
              <div className="space-y-1.5 max-h-48 overflow-y-auto">
                {currentTask.microSteps.map((step) => (
                  <button
                    key={step.id}
                    onClick={() => handleToggleMicroStep(currentTask, step.id)}
                    className="w-full flex items-center gap-2.5 p-2.5 rounded-xl bg-[#1C1C1F] hover:bg-[#212124] border border-[#232326] text-left transition-colors"
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
                ))}
              </div>
            </div>
          )}

          {/* Control Actions: Pause & Park, and Finish */}
          <div className="flex flex-col sm:flex-row items-center justify-between gap-3 pt-3 border-t border-[#232326]">
            <button
              onClick={() => handlePause(currentTask.id)}
              className="w-full sm:w-auto flex items-center justify-center gap-2 px-5 py-3 rounded-2xl bg-[#212124] hover:bg-[#28282C] text-xs font-semibold text-[#D9A441] border border-[#D9A441]/30 transition-all active:scale-98"
            >
              <Pause className="w-4 h-4" />
              <span>Pause & Park</span>
            </button>

            <button
              onClick={() => handleFinish(currentTask.id)}
              className="w-full sm:w-auto flex items-center justify-center gap-2 px-7 py-3 rounded-2xl bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] text-sm font-bold transition-all shadow-lg shadow-[#2FB083]/25 active:scale-98"
            >
              <CheckCircle2 className="w-4 h-4 stroke-[2.5]" />
              <span>Finish Task</span>
            </button>
          </div>
        </div>
      )}

      {/* Clarify Modal */}
      {clarifyingTask && (
        <ClarifyModal
          task={clarifyingTask}
          isOpen={Boolean(clarifyingTask)}
          onClose={() => setClarifyingTask(null)}
          onClarified={() => {
            refresh();
            setClarifyingTask(null);
          }}
          onClarifyAndPick={(t) => {
            refresh();
            setClarifyingTask(null);
          }}
        />
      )}
    </div>
  );
};
