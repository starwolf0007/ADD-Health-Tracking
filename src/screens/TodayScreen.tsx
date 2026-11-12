import React, { useState, useEffect } from 'react';
import {
  ChevronLeft,
  ChevronRight,
  Sparkles,
  Zap,
  CheckCircle2,
  Circle,
  Play,
  Pause,
  Repeat,
  ArrowRight,
  Edit2,
  Clock,
  Scissors,
  Check,
  RotateCcw,
  Maximize2,
  BookmarkCheck,
  SlidersHorizontal,
} from 'lucide-react';
import { Task, Routine, Habit, Achievement, EnergyLevel } from '../types';
import {
  isSameDay,
  taskStorage,
  habitStorage,
} from '../lib/storage';
import {
  Executive,
  DaySummary,
  buildTimeline,
  getTimelineItemPhase,
  sliceTaskIntoMicroSteps,
  InlineMicroStep,
} from '../lib/executive';
import { LexiAvatar } from '../components/LexiAvatar';
import { CaptureSheet } from '../components/CaptureSheet';
import { TaskEditSheet } from '../components/TaskEditSheet';
import { ReentryModal } from '../components/ReentryModal';

interface TodayScreenProps {
  tasks: Task[];
  routines: Routine[];
  habits: Habit[];
  todayMood: any;
  onOpenLexi: () => void;
  onOpenSettings: () => void;
  onLaunchRoutine: (routine: Routine) => void;
  onTriggerAchievement: (achievement: Achievement) => void;
  onOpenVisualTimer?: (task?: Task | null, initialMinutes?: number) => void;
  refresh: () => void;
}

const HEARTBEAT_PATTERN = [6, 9, 14, 20, 11, 6, 8, 22, 7, 11, 6, 16, 9, 6, 18, 8, 6, 13, 7, 10];

/**
 * Monochrome shape-distinguished energy glyph per Unified Spec §13
 */
const EnergyGlyph: React.FC<{ energy: EnergyLevel }> = ({ energy }) => {
  if (energy === 'low') {
    return (
      <svg className="w-3.5 h-3.5 text-[#8A8A8E]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <rect x="3" y="8" width="15" height="8" rx="2" />
        <path d="M20 10.5v3" />
        <rect x="5.5" y="10.5" width="3.5" height="3" fill="currentColor" stroke="none" />
      </svg>
    );
  }
  if (energy === 'high') {
    return (
      <svg className="w-3.5 h-3.5 text-[#8A8A8E]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
        <path d="M13 3L6 13.5h5L10.5 21 18 10.5h-5L13 3z" />
      </svg>
    );
  }
  return (
    <svg className="w-3.5 h-3.5 text-[#8A8A8E]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="7" />
    </svg>
  );
};

export const TodayScreen: React.FC<TodayScreenProps> = ({
  tasks,
  routines,
  habits,
  todayMood,
  onOpenLexi,
  onLaunchRoutine,
  onTriggerAchievement,
  onOpenVisualTimer,
  refresh,
}) => {
  const [selectedDay, setSelectedDay] = useState<Date>(new Date());
  const [isCaptureOpen, setIsCaptureOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  const [reentryTask, setReentryTask] = useState<Task | null>(null);

  // Inline Focus Pod state (Make it smaller + inline timer + 3-stop haptic difficulty)
  const [slicedTaskId, setSlicedTaskId] = useState<string | null>(null);
  const [microSteps, setMicroSteps] = useState<InlineMicroStep[]>([]);
  const [targetMinutes, setTargetMinutes] = useState<number>(15);
  const [elapsedSeconds, setElapsedSeconds] = useState<number>(0);
  const [difficultyStop, setDifficultyStop] = useState<'light' | 'steady' | 'heavy' | null>(null);

  const isToday = isSameDay(selectedDay, new Date());
  const pendingTasks = tasks.filter((t) => t.status !== 'completed');
  const completedTodayCount = tasks.filter(
    (t) => t.status === 'completed' && (!t.completedAt || isSameDay(new Date(t.completedAt), selectedDay))
  ).length;

  // Executive evaluation: automatically swaps mode based on today's mood
  const currentMoodLevel = isToday ? todayMood?.level : null;
  const plan = Executive.evaluate(pendingTasks, currentMoodLevel);
  const isQuickWins = isToday && plan.mode === 'quickWins' && plan.quickWins.length > 0;
  const primaryTask = plan.primaryTask;

  // Sync inline Focus Pod timer & micro-steps when primaryTask changes
  useEffect(() => {
    if (!primaryTask) {
      setElapsedSeconds(0);
      return;
    }
    setTargetMinutes(primaryTask.estimatedMinutes || 15);

    // If task already has markdown steps in notes, auto-open them in the Focus Pod
    if (primaryTask.notes && /^\s*-\s*\[[ xX]\]/m.test(primaryTask.notes)) {
      setSlicedTaskId(primaryTask.id);
      setMicroSteps(sliceTaskIntoMicroSteps(primaryTask));
    } else if (slicedTaskId === primaryTask.id) {
      setMicroSteps(sliceTaskIntoMicroSteps(primaryTask));
    }

    if (primaryTask.status === 'inProgress' && primaryTask.activeStartedAt) {
      const startedMs = new Date(primaryTask.activeStartedAt).getTime();
      const initialElapsed = Math.max(0, Math.floor((Date.now() - startedMs) / 1000));
      setElapsedSeconds(initialElapsed);
    } else {
      setElapsedSeconds(0);
    }
  }, [primaryTask?.id, primaryTask?.status, primaryTask?.activeStartedAt]);

  // Live 1-second tick when primary task is inProgress
  useEffect(() => {
    if (!primaryTask || primaryTask.status !== 'inProgress') return;
    const interval = setInterval(() => {
      if (primaryTask.activeStartedAt) {
        const startedMs = new Date(primaryTask.activeStartedAt).getTime();
        setElapsedSeconds(Math.max(0, Math.floor((Date.now() - startedMs) / 1000)));
      } else {
        setElapsedSeconds((prev) => prev + 1);
      }
    }, 1000);
    return () => clearInterval(interval);
  }, [primaryTask?.id, primaryTask?.status, primaryTask?.activeStartedAt]);

  // Build timeline for selected day
  const timelineItems = buildTimeline(selectedDay, tasks, routines);
  const now = new Date();

  // Navigation helpers
  const handlePrevDay = () => {
    setSelectedDay((prev) => new Date(prev.getTime() - 86400000));
  };
  const handleNextDay = () => {
    setSelectedDay((prev) => new Date(prev.getTime() + 86400000));
  };
  const handleGoToToday = () => {
    setSelectedDay(new Date());
  };

  const triggerHaptic = (ms = 12) => {
    try {
      if (typeof navigator !== 'undefined' && navigator.vibrate) {
        navigator.vibrate(ms);
      }
    } catch {
      // Ignore on unsupported browsers
    }
  };

  const handleToggleTask = (task: Task) => {
    triggerHaptic(18);
    const wasPaused = task.status === 'paused';
    const updated = taskStorage.toggleStatus(task.id);
    if (updated && updated.status === 'completed' && wasPaused) {
      onTriggerAchievement({
        id: `reentry-${Date.now()}`,
        title: 'RE-ENTRY COMPLETE',
        message: 'Picked right back up from your saved checkpoint and finished.',
        type: 'reentry',
        timestamp: Date.now(),
      });
    }
    refresh();
  };

  const handleStartTask = (task: Task, customTargetMinutes?: number) => {
    triggerHaptic(15);
    if (customTargetMinutes) {
      setTargetMinutes(customTargetMinutes);
    }
    taskStorage.startTask(task.id);
    refresh();
  };

  const handlePauseTask = (task: Task) => {
    triggerHaptic(10);
    setReentryTask(task);
  };

  const handleSliceTaskInline = (task: Task) => {
    triggerHaptic(12);
    if (slicedTaskId === task.id && microSteps.length > 0) {
      setSlicedTaskId(null);
      return;
    }
    const generated = sliceTaskIntoMicroSteps(task);
    setSlicedTaskId(task.id);
    setMicroSteps(generated);

    // Persist the micro-steps on the task so they survive app reload
    const checklistText = generated
      .map((s) => `- [${s.done ? 'x' : ' '}] ${s.title} (${s.minutes}m)`)
      .join('\n');
    const cleanExistingNotes = (task.notes || '')
      .split('\n')
      .filter((line) => !/^\s*-\s*\[[ xX]\]/.test(line))
      .join('\n')
      .trim();
    const updatedNotes = cleanExistingNotes
      ? `${cleanExistingNotes}\n${checklistText}`
      : checklistText;

    taskStorage.save({
      ...task,
      notes: updatedNotes,
      reentryNote: {
        lastCompletedStep: task.reentryNote?.lastCompletedStep || 'Sliced into 3 concrete steps',
        nextAction: generated.find((s) => !s.done)?.title || generated[0]?.title,
        updatedAt: new Date().toISOString(),
      },
    });
    refresh();
  };

  const handleToggleMicroStep = (task: Task, stepId: string) => {
    triggerHaptic(15);
    const updatedSteps = microSteps.map((s) =>
      s.id === stepId ? { ...s, done: !s.done } : s
    );
    setMicroSteps(updatedSteps);

    const lastDone = [...updatedSteps].reverse().find((s) => s.done);
    const nextPending = updatedSteps.find((s) => !s.done);

    const checklistText = updatedSteps
      .map((s) => `- [${s.done ? 'x' : ' '}] ${s.title} (${s.minutes}m)`)
      .join('\n');
    const cleanExistingNotes = (task.notes || '')
      .split('\n')
      .filter((line) => !/^\s*-\s*\[[ xX]\]/.test(line))
      .join('\n')
      .trim();
    const updatedNotes = cleanExistingNotes
      ? `${cleanExistingNotes}\n${checklistText}`
      : checklistText;

    // Save durable checkpoint without prematurely marking parent task completed (Manifest §28.2)
    taskStorage.save({
      ...task,
      notes: updatedNotes,
      reentryNote: {
        lastCompletedStep: lastDone ? lastDone.title : 'Started micro-steps',
        nextAction: nextPending ? nextPending.title : 'Ready to mark task complete',
        updatedAt: new Date().toISOString(),
      },
    });
    refresh();
  };

  const handleConfirmReentry = (lastStep: string, nextAction: string) => {
    if (!reentryTask) return;
    const nextMicroStep =
      slicedTaskId === reentryTask.id ? microSteps.find((s) => !s.done)?.title : undefined;
    const lastMicroStep =
      slicedTaskId === reentryTask.id
        ? [...microSteps].reverse().find((s) => s.done)?.title
        : undefined;

    const updated: Task = {
      ...reentryTask,
      status: 'paused',
      reentryNote: {
        lastCompletedStep: lastStep || lastMicroStep || 'Paused cleanly',
        nextAction: nextAction || nextMicroStep || 'Open task and take the first 2-minute step',
        updatedAt: new Date().toISOString(),
      },
    };
    taskStorage.save(updated);
    refresh();
  };

  const handleToggleHabit = (habitId: string) => {
    triggerHaptic(12);
    if (habitStorage.isCheckedToday(habitId)) {
      habitStorage.uncheck(habitId);
    } else {
      habitStorage.checkIn(habitId);
    }
    refresh();
  };

  const handleSelectDifficulty = (stop: 'light' | 'steady' | 'heavy') => {
    triggerHaptic(10);
    setDifficultyStop((prev) => (prev === stop ? null : stop));
  };

  // Fixed items (for Quick Wins view)
  const fixedItems = timelineItems.filter(
    (item) => item.type === 'fixedAnchor' || item.type === 'calendarEvent'
  );

  const dayItems = timelineItems.filter((item) => item.type !== 'flexibleBlock');
  const flexibleItems = timelineItems.filter((item) => item.type === 'flexibleBlock');

  // Find index for the current time marker
  const markerIndex = dayItems.findIndex(
    (item) => getTimelineItemPhase(item, now) !== 'past'
  );

  // Compute Heartbeat progress ratio across tasks + routines + habits
  const completedRoutinesCount = routines.filter(
    (r) => r.steps.length > 0 && r.steps.every((s) => s.isComplete)
  ).length;
  const completedHabitsCount = habits.slice(0, 3).filter((h) => habitStorage.isCheckedToday(h.id)).length;
  const totalDayUnits = Math.max(
    1,
    completedTodayCount + pendingTasks.length + routines.length + Math.min(3, habits.length)
  );
  const completedDayUnits = completedTodayCount + completedRoutinesCount + completedHabitsCount;
  const filledBarsCount = Math.max(
    completedDayUnits > 0 ? 2 : 0,
    Math.round((completedDayUnits / totalDayUnits) * HEARTBEAT_PATTERN.length)
  );

  // Format Focus Pod clock
  const elapsedMins = Math.floor(elapsedSeconds / 60);
  const elapsedSecs = elapsedSeconds % 60;
  const clockDisplay = `${elapsedMins}:${String(elapsedSecs).padStart(2, '0')}`;
  const targetTotalSeconds = Math.max(60, targetMinutes * 60);
  const isOvertime = elapsedSeconds >= targetTotalSeconds;
  const progressPercent = Math.min(100, Math.round((elapsedSeconds / targetTotalSeconds) * 100));

  // Filter non-checklist notes for clean display
  const getCleanNotes = (notes?: string) => {
    if (!notes) return '';
    return notes
      .split('\n')
      .filter((line) => !/^\s*-\s*\[[ xX]\]/.test(line) && !/^Breakdown steps:$/i.test(line.trim()))
      .join('\n')
      .trim();
  };

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-5">
      {/* Top Header + Heartbeat Progress Strip (from neuroflow-v2-preview.html) */}
      <div className="space-y-2.5">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs text-[#8A8A8E] font-medium">
              {selectedDay.toLocaleDateString(undefined, {
                weekday: 'long',
                month: 'short',
                day: 'numeric',
              })}
            </div>
            <div className="flex items-center gap-2.5 mt-0.5">
              <h2 className="text-xl font-semibold text-[#F0F0F0] tracking-tight">
                {isToday ? 'Today' : 'Day Plan'}
              </h2>
              {completedDayUnits > 0 && (
                <span className="inline-flex items-center gap-1 text-xs font-medium text-[#2FB083] bg-[#2FB083]/10 px-2.5 py-0.5 rounded-full">
                  <Check className="w-3 h-3 stroke-[2.5]" />
                  <span>{completedDayUnits} done</span>
                </span>
              )}
            </div>
          </div>

          {/* Compact Date Stepper */}
          <div className="flex items-center gap-1 bg-[#161618] border border-[#232326] rounded-full px-1.5 py-1">
            <button
              onClick={handlePrevDay}
              className="p-1 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-full transition-colors"
              title="Previous day"
            >
              <ChevronLeft className="w-4 h-4" />
            </button>
            {!isToday && (
              <button
                onClick={handleGoToToday}
                className="text-[11px] font-medium text-[#2FB083] px-2 py-0.5 rounded-full bg-[#2FB083]/10 hover:bg-[#2FB083]/20 transition-colors"
              >
                Today
              </button>
            )}
            <button
              onClick={handleNextDay}
              className="p-1 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-full transition-colors"
              title="Next day"
            >
              <ChevronRight className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Static-fill Heartbeat Waveform Strip (updates on state transitions per Spec §13) */}
        <div
          className="flex items-center gap-[3px] h-5 pt-0.5"
          title={`${completedDayUnits} of ${totalDayUnits} daily steps completed`}
        >
          {HEARTBEAT_PATTERN.map((heightPx, idx) => {
            const isFilled = idx < filledBarsCount;
            return (
              <div
                key={idx}
                className="w-[3.5px] rounded-full transition-colors duration-300"
                style={{
                  height: `${heightPx}px`,
                  backgroundColor: isFilled ? '#2FB083' : '#232326',
                }}
              />
            );
          })}
        </div>
      </div>

      {/* Ambient Contextual Lexi Presence (Living Companion Cue) */}
      <div
        onClick={onOpenLexi}
        className="group relative bg-gradient-to-br from-[#1C1C1F] to-[#161618] border border-[#232326] hover:border-[#BB86FC]/40 rounded-2xl p-4 shadow-lg cursor-pointer transition-all flex items-start gap-3.5"
      >
        <LexiAvatar
          size={48}
          visualState={
            primaryTask?.status === 'inProgress'
              ? 'focus'
              : primaryTask?.status === 'paused'
              ? 'transition'
              : isQuickWins
              ? 'evening'
              : 'idle'
          }
        />
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-semibold tracking-wider text-[#BB86FC] uppercase flex items-center gap-1.5">
              <span>Lexi</span>
              <span className="text-[#555559]">·</span>
              <span className="text-[#8A8A8E] font-normal normal-case">
                {DaySummary.build(timelineItems)}
              </span>
            </span>
            <span className="text-[11px] text-[#8A8A8E] group-hover:text-[#BB86FC] transition-colors shrink-0">
              Talk →
            </span>
          </div>
          <p className="text-sm text-[#F0F0F0] mt-1.5 leading-relaxed">
            {DaySummary.buildLexiCue(timelineItems, primaryTask, isQuickWins, now)}
          </p>
        </div>
      </div>

      {/* QUICK WINS MODE (Auto-swapped if mood is rough/low per spec §6) */}
      {isQuickWins ? (
        <section className="bg-[#1C1C1F] border border-[#2FB083]/30 rounded-2xl p-5 shadow-xl space-y-3.5">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <div className="w-6 h-6 rounded-full bg-[#2FB083]/20 flex items-center justify-center">
                <Zap className="w-3.5 h-3.5 text-[#2FB083]" />
              </div>
              <h3 className="text-xs font-semibold tracking-wider text-[#2FB083] uppercase">
                Quick Wins
              </h3>
            </div>
            <span className="text-[11px] text-[#8A8A8E]">Capped at 3</span>
          </div>

          <p className="text-sm text-[#8A8A8E] leading-relaxed">
            Lighter load today — showing your easiest wins first.{' '}
            <span className="text-[#F0F0F0] font-medium">Nothing else is tracked today.</span>
          </p>

          <div className="space-y-2.5 pt-1">
            {plan.quickWins.map((task) => (
              <div
                key={task.id}
                onClick={() => handleToggleTask(task)}
                className="flex items-center gap-3.5 p-4 rounded-xl bg-[#161618] border border-[#232326] hover:border-[#2FB083]/50 cursor-pointer transition-all active:scale-[0.99]"
              >
                <div className="w-6 h-6 rounded-lg border border-[#555559] flex items-center justify-center text-[#2FB083] shrink-0">
                  <Check className="w-3.5 h-3.5 opacity-0 hover:opacity-100 transition-opacity" />
                </div>
                <div className="flex-1 min-w-0">
                  <span className="text-[15px] text-[#F0F0F0] font-medium leading-snug block">
                    {task.title}
                  </span>
                  {getCleanNotes(task.notes) && (
                    <span className="text-xs text-[#8A8A8E] block truncate mt-0.5">
                      {getCleanNotes(task.notes)}
                    </span>
                  )}
                </div>
                <span className="text-xs font-mono px-2.5 py-1 rounded-lg bg-[#2FB083]/10 text-[#2FB083]">
                  {task.estimatedMinutes ? `~${task.estimatedMinutes}m` : 'Quick'}
                </span>
              </div>
            ))}
          </div>

          {fixedItems.length > 0 && (
            <div className="pt-3 border-t border-[#232326] space-y-2">
              <h4 className="text-[11px] font-semibold text-[#8A8A8E] uppercase tracking-wider">
                Still anchored today
              </h4>
              {fixedItems.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between p-2.5 rounded-xl bg-[#161618] text-xs text-[#8A8A8E]"
                >
                  <span className="font-medium text-[#F0F0F0]">{item.title}</span>
                  <span>{item.subtitle}</span>
                </div>
              ))}
            </div>
          )}
        </section>
      ) : (
        /* STANDARD MODE — HERO ONE-TAP FOCUS POD + YOUR DAY RIVER */
        <>
          {primaryTask && isToday ? (
            <section className="space-y-2">
              <div className="flex items-center justify-between px-1">
                <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8A8A8E]">
                  {primaryTask.status === 'inProgress'
                    ? 'Active Focus Pod'
                    : primaryTask.status === 'paused'
                    ? 'Saved Re-Entry Card'
                    : 'Next Up'}
                </span>
                <button
                  onClick={() => setEditingTask(primaryTask)}
                  className="text-xs text-[#8A8A8E] hover:text-[#F0F0F0] flex items-center gap-1 transition-colors"
                >
                  <Edit2 className="w-3 h-3" />
                  <span>Edit</span>
                </button>
              </div>

              <div
                className={`rounded-2xl p-5 border transition-all shadow-xl ${
                  primaryTask.status === 'inProgress'
                    ? 'bg-[#1C1C1F] border-[#2FB083]/60 shadow-[#2FB083]/10'
                    : primaryTask.status === 'paused'
                    ? 'bg-[#1C1C1F] border-[#D9A441]/50 shadow-[#D9A441]/5'
                    : 'bg-[#161618] border-[#232326]'
                }`}
              >
                {/* Top Metadata Row: Monochrome Energy Glyph + Duration Pill + Haptic Difficulty */}
                <div className="flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2 text-xs text-[#8A8A8E]">
                    <EnergyGlyph energy={primaryTask.energy} />
                    <span>{primaryTask.energy} energy</span>
                    <span>·</span>
                    <span>~{primaryTask.estimatedMinutes ?? 15} min</span>
                  </div>

                  {/* 3-Stop Haptic Difficulty Selector (Spec v1.9 §4.2.1b — skippable, non-blocking) */}
                  <div
                    className="flex items-center gap-1 bg-[#212124] p-0.5 rounded-lg border border-[#232326]"
                    title="Optional perceived friction check (skippable)"
                  >
                    <SlidersHorizontal className="w-3 h-3 text-[#555559] ml-1.5 mr-0.5" />
                    {(['light', 'steady', 'heavy'] as const).map((stop) => (
                      <button
                        key={stop}
                        type="button"
                        onClick={() => handleSelectDifficulty(stop)}
                        className={`px-2 py-0.5 rounded-md text-[10px] font-medium capitalize transition-all ${
                          difficultyStop === stop
                            ? 'bg-[#2FB083]/20 text-[#2FB083] border border-[#2FB083]/40'
                            : 'text-[#8A8A8E] hover:text-[#F0F0F0]'
                        }`}
                      >
                        {stop}
                      </button>
                    ))}
                  </div>
                </div>

                {/* Hero Task Title (28px–30px per neuroflow-v2-preview.html) */}
                <h1 className="text-2xl sm:text-[28px] font-normal text-[#F0F0F0] leading-tight tracking-tight mt-3">
                  {primaryTask.title}
                </h1>

                {getCleanNotes(primaryTask.notes) && (
                  <p className="text-sm text-[#8A8A8E] mt-2 leading-relaxed">
                    {getCleanNotes(primaryTask.notes)}
                  </p>
                )}

                {/* Re-Entry Card Banner (if task is paused with a saved checkpoint) */}
                {primaryTask.status === 'paused' && primaryTask.reentryNote && (
                  <div className="mt-4 bg-[#D9A441]/10 border border-[#D9A441]/30 rounded-xl p-3.5 space-y-1">
                    <div className="flex items-center justify-between">
                      <span className="text-[11px] font-semibold uppercase tracking-wider text-[#D9A441] flex items-center gap-1.5">
                        <BookmarkCheck className="w-3.5 h-3.5" />
                        <span>Return point preserved</span>
                      </span>
                      {primaryTask.reentryNote.lastCompletedStep && (
                        <span className="text-[11px] text-[#8A8A8E] truncate max-w-[180px]">
                          Last: {primaryTask.reentryNote.lastCompletedStep}
                        </span>
                      )}
                    </div>
                    <p className="text-sm font-medium text-[#F0F0F0]">
                      Next physical step:{' '}
                      <span className="text-[#D9A441]">
                        {primaryTask.reentryNote.nextAction || 'Open task and begin step one'}
                      </span>
                    </p>
                  </div>
                )}

                {/* Inline Live Focus Timer (when task is inProgress) */}
                {primaryTask.status === 'inProgress' && (
                  <div className="mt-5 pt-4 border-t border-[#232326] space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-1.5">
                        {[5, 15, 25, 45].map((mins) => (
                          <button
                            key={mins}
                            type="button"
                            onClick={() => setTargetMinutes(mins)}
                            className={`px-2.5 py-1 rounded-lg text-xs font-medium transition-colors ${
                              targetMinutes === mins
                                ? 'bg-[#2FB083]/20 text-[#2FB083] border border-[#2FB083]/40'
                                : 'bg-[#212124] text-[#8A8A8E] hover:text-[#F0F0F0]'
                            }`}
                          >
                            {mins}m
                          </button>
                        ))}
                      </div>
                      {onOpenVisualTimer && (
                        <button
                          type="button"
                          onClick={() => onOpenVisualTimer(primaryTask, targetMinutes)}
                          className="text-xs text-[#8A8A8E] hover:text-[#2FB083] flex items-center gap-1 transition-colors"
                          title="Open fullscreen radial clock"
                        >
                          <Maximize2 className="w-3.5 h-3.5" />
                          <span>Fullscreen Clock</span>
                        </button>
                      )}
                    </div>

                    <div className="text-center py-1">
                      <div
                        className={`font-mono text-4xl sm:text-[44px] font-medium tracking-wider tabular-nums ${
                          isOvertime ? 'text-[#D9A441]' : 'text-[#F0F0F0]'
                        }`}
                      >
                        {clockDisplay}
                      </div>
                      <div className="h-1.5 w-full bg-[#232326] rounded-full overflow-hidden mt-3">
                        <div
                          className={`h-full transition-all duration-1000 ${
                            isOvertime ? 'bg-[#D9A441]' : 'bg-[#2FB083]'
                          }`}
                          style={{ width: `${progressPercent}%` }}
                        />
                      </div>
                      <p className="text-xs text-[#8A8A8E] mt-2">
                        {isOvertime
                          ? `Target ${targetMinutes}m reached · In the flow (no-guilt overtime)`
                          : `Target ${targetMinutes} min · ~${Math.max(
                              1,
                              targetMinutes - elapsedMins
                            )} min left`}
                      </p>
                    </div>
                  </div>
                )}

                {/* Inline Micro-Steps Drawer ("Make it smaller" — G-002 / MU-003) */}
                {slicedTaskId === primaryTask.id && microSteps.length > 0 && (
                  <div className="mt-4 pt-3.5 border-t border-[#232326] space-y-2">
                    <div className="flex items-center justify-between">
                      <span className="text-[11px] font-semibold uppercase tracking-wider text-[#2FB083]">
                        Bite-Sized Steps (Tap as you go)
                      </span>
                      <span className="text-[11px] text-[#8A8A8E]">
                        {microSteps.filter((s) => s.done).length}/{microSteps.length} steps
                      </span>
                    </div>
                    <div className="space-y-1.5">
                      {microSteps.map((step, idx) => (
                        <div
                          key={step.id}
                          onClick={() => handleToggleMicroStep(primaryTask, step.id)}
                          className={`flex items-center justify-between gap-3 p-3 rounded-xl border cursor-pointer transition-all ${
                            step.done
                              ? 'bg-[#161618]/60 border-[#232326] opacity-60'
                              : idx === microSteps.findIndex((s) => !s.done)
                              ? 'bg-[#212124] border-[#2FB083]/40'
                              : 'bg-[#161618] border-[#232326] hover:border-[#2FB083]/30'
                          }`}
                        >
                          <div className="flex items-center gap-3 min-w-0 flex-1">
                            <div
                              className={`w-5 h-5 rounded-md border flex items-center justify-center shrink-0 transition-colors ${
                                step.done
                                  ? 'bg-[#2FB083] border-[#2FB083] text-[#0C0C0D]'
                                  : 'border-[#555559]'
                              }`}
                            >
                              {step.done && <Check className="w-3.5 h-3.5 stroke-[2.5]" />}
                            </div>
                            <span
                              className={`text-sm leading-snug ${
                                step.done
                                  ? 'line-through text-[#8A8A8E]'
                                  : 'text-[#F0F0F0] font-medium'
                              }`}
                            >
                              {step.title}
                            </span>
                          </div>
                          <span className="text-[11px] font-mono text-[#8A8A8E] shrink-0">
                            ~{step.minutes}m
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}

                {/* Primary & Secondary Action Bar */}
                <div className="mt-5 space-y-2.5">
                  {primaryTask.status !== 'inProgress' ? (
                    <div className="flex items-center gap-2.5">
                      <button
                        onClick={() => handleStartTask(primaryTask)}
                        className="flex-1 min-h-[50px] py-3 px-4 bg-[#2FB083] hover:bg-[#2FB083]/90 active:bg-[#1E7A5A] text-[#0C0C0D] rounded-xl text-[15px] font-semibold flex items-center justify-center gap-2 transition-all shadow-md shadow-[#2FB083]/15"
                      >
                        {primaryTask.status === 'paused' ? (
                          <>
                            <RotateCcw className="w-4 h-4 stroke-[2.2]" />
                            <span>Resume From Checkpoint</span>
                          </>
                        ) : (
                          <>
                            <Play className="w-4 h-4 fill-current" />
                            <span>Start Focus</span>
                          </>
                        )}
                      </button>

                      <button
                        onClick={() => handleToggleTask(primaryTask)}
                        className="min-h-[50px] py-3 px-4 bg-[#212124] hover:bg-[#28282C] text-[#F0F0F0] border border-[#232326] rounded-xl text-sm font-medium flex items-center gap-1.5 transition-colors"
                        title="Mark task done"
                      >
                        <CheckCircle2 className="w-4 h-4 text-[#2FB083]" />
                        <span>Done</span>
                      </button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-2.5">
                      <button
                        onClick={() => handleToggleTask(primaryTask)}
                        className="flex-1 min-h-[50px] py-3 px-4 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-[15px] font-semibold flex items-center justify-center gap-2 transition-all shadow-md shadow-[#2FB083]/15"
                      >
                        <CheckCircle2 className="w-4 h-4 stroke-[2.5]" />
                        <span>Done</span>
                      </button>

                      <button
                        onClick={() => handlePauseTask(primaryTask)}
                        className="min-h-[50px] py-3 px-4 bg-[#212124] hover:bg-[#28282C] text-[#D9A441] border border-[#D9A441]/30 rounded-xl text-sm font-semibold flex items-center justify-center gap-1.5 transition-colors"
                      >
                        <Pause className="w-4 h-4" />
                        <span>Pause & Park</span>
                      </button>
                    </div>
                  )}

                  {/* Low-friction secondary tools row: Make it smaller · Quick timer presets · Body Double */}
                  <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => handleSliceTaskInline(primaryTask)}
                      className={`inline-flex items-center gap-1.5 px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${
                        slicedTaskId === primaryTask.id
                          ? 'bg-[#2FB083]/15 text-[#2FB083] border-[#2FB083]/40'
                          : 'bg-[#212124] text-[#8A8A8E] hover:text-[#F0F0F0] border-[#232326]'
                      }`}
                    >
                      <Scissors className="w-3.5 h-3.5" />
                      <span>
                        {slicedTaskId === primaryTask.id ? 'Hide micro-steps' : 'Make it smaller'}
                      </span>
                    </button>

                    <div className="flex items-center gap-1.5">
                      {primaryTask.status !== 'inProgress' && (
                        <>
                          <button
                            type="button"
                            onClick={() => handleStartTask(primaryTask, 5)}
                            className="px-2.5 py-1.5 rounded-xl bg-[#212124] hover:bg-[#2FB083]/15 text-[#8A8A8E] hover:text-[#2FB083] border border-[#232326] text-xs font-medium transition-colors"
                            title="Just start for 5 minutes"
                          >
                            5m start
                          </button>
                          {onOpenVisualTimer && (
                            <button
                              type="button"
                              onClick={() => onOpenVisualTimer(primaryTask, 25)}
                              className="px-2.5 py-1.5 rounded-xl bg-[#212124] hover:bg-[#2FB083]/15 text-[#8A8A8E] hover:text-[#2FB083] border border-[#232326] text-xs font-medium flex items-center gap-1 transition-colors"
                              title="Open visual radial timer"
                            >
                              <Clock className="w-3.5 h-3.5" />
                              <span>25m</span>
                            </button>
                          )}
                        </>
                      )}

                      <button
                        type="button"
                        onClick={onOpenLexi}
                        className="px-3 py-1.5 rounded-xl bg-[#BB86FC]/12 hover:bg-[#BB86FC]/20 text-[#BB86FC] border border-[#BB86FC]/25 text-xs font-medium flex items-center gap-1.5 transition-colors"
                        title="Body double or brainstorm with Lexi"
                      >
                        <Sparkles className="w-3.5 h-3.5" />
                        <span>Body Double</span>
                      </button>
                    </div>
                  </div>
                </div>
              </div>

              {plan.reason && (
                <p className="text-xs text-[#8A8A8E] px-1 pt-0.5">{plan.reason}</p>
              )}
            </section>
          ) : (
            isToday && (
              <div className="py-12 px-5 text-center bg-[#161618] border border-[#232326] rounded-2xl space-y-2">
                <CheckCircle2 className="w-9 h-9 text-[#2FB083]/70 mx-auto stroke-[1.6]" />
                <h3 className="text-base font-medium text-[#F0F0F0]">All clear right now</h3>
                <p className="text-xs text-[#8A8A8E]">
                  Nothing pending on your active list. Enjoy the margin or capture a new thought.
                </p>
              </div>
            )
          )}

          {/* Due Routines Strip (Sleek one-tap rows matching neuroflow-v2-preview.html) */}
          {isToday && routines.length > 0 && (
            <section className="space-y-2">
              <div className="flex items-center justify-between px-1">
                <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8A8A8E]">
                  Routines
                </span>
              </div>

              <div className="space-y-2">
                {routines.map((routine) => {
                  const completedCount = routine.steps.filter((s) => s.isComplete).length;
                  const totalCount = routine.steps.length;
                  const isAllDone = totalCount > 0 && completedCount === totalCount;

                  return (
                    <div
                      key={routine.id}
                      onClick={() => onLaunchRoutine(routine)}
                      className="p-3.5 rounded-2xl bg-[#161618] hover:bg-[#1C1C1F] border border-[#232326] cursor-pointer transition-all flex items-center justify-between gap-4"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <Repeat className="w-4 h-4 text-[#2FB083] shrink-0" />
                          <h4
                            className={`text-[15px] font-medium truncate ${
                              isAllDone ? 'line-through text-[#8A8A8E]' : 'text-[#F0F0F0]'
                            }`}
                          >
                            {routine.name}
                          </h4>
                        </div>
                        {/* Mini step progress bars (from neuroflow-voice-timeline-mock.html) */}
                        <div className="flex items-center gap-1.5 mt-2">
                          {routine.steps.map((s) => (
                            <div
                              key={s.id}
                              className={`h-1 flex-1 rounded-full ${
                                s.isComplete ? 'bg-[#2FB083]' : 'bg-[#232326]'
                              }`}
                            />
                          ))}
                        </div>
                      </div>

                      <div className="flex items-center gap-2.5 shrink-0">
                        <span className="text-xs font-mono text-[#8A8A8E]">
                          {completedCount}/{totalCount}
                        </span>
                        <ArrowRight className="w-4 h-4 text-[#555559]" />
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>
          )}

          {/* YOUR DAY — Connected Vertical Timeline River (from neuroflow-voice-timeline-mock.html) */}
          <section className="space-y-3 pt-1">
            <div className="flex items-center justify-between px-1">
              <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8A8A8E]">
                {isToday ? 'Your Day' : 'Day Schedule'}
              </span>
              <span className="text-[11px] text-[#555559]">
                Anchors + Flex
              </span>
            </div>

            {dayItems.length === 0 ? (
              <div className="p-6 text-center border border-dashed border-[#232326] rounded-2xl text-xs text-[#8A8A8E]">
                No fixed anchors scheduled for this day.
              </div>
            ) : (
              <div className="relative pl-14 pr-1 py-1 space-y-3">
                {/* Vertical Spine Line */}
                <div className="absolute left-[46px] top-3 bottom-3 w-[2px] bg-[#232326] rounded-full" />

                {dayItems.map((item, index) => {
                  const isCurrent = isToday && index === markerIndex;
                  const isCompleted = item.isCompleted;
                  const timeLabel = item.start
                    ? new Date(item.start).toLocaleTimeString([], {
                        hour: 'numeric',
                        minute: '2-digit',
                        hour12: false,
                      })
                    : '';

                  return (
                    <React.Fragment key={item.id}>
                      {/* Glowing NOW Line */}
                      {isCurrent && (
                        <div className="relative flex items-center py-1.5">
                          <span className="absolute -left-14 w-10 text-right font-mono text-[11px] font-semibold text-[#2FB083]">
                            now
                          </span>
                          <span className="absolute -left-[22px] w-2.5 h-2.5 rounded-full bg-[#2FB083] ring-4 ring-[#2FB083]/20" />
                          <div className="w-full h-[2px] bg-[#2FB083] rounded-full shadow-[0_0_8px_rgba(47,176,131,0.45)]" />
                        </div>
                      )}

                      {/* Timeline River Node + Block */}
                      <div className="relative">
                        {timeLabel && (
                          <span className="absolute -left-14 top-3 w-10 text-right font-mono text-[11px] text-[#555559] tabular-nums">
                            {timeLabel}
                          </span>
                        )}

                        {/* Spine Node Dot */}
                        <span
                          className={`absolute -left-[22px] top-3.5 w-2.5 h-2.5 rounded-full border-2 border-[#0C0C0D] ${
                            item.type === 'openSpace'
                              ? 'bg-[#3C3C40]'
                              : isCompleted
                              ? 'bg-[#2FB083]'
                              : item.isPaused
                              ? 'bg-[#D9A441]'
                              : item.type === 'fixedAnchor'
                              ? 'bg-[#2FB083]/80'
                              : 'bg-[#8A8A8E]'
                          }`}
                        />

                        {item.type === 'openSpace' ? (
                          <div className="px-3.5 py-2.5 rounded-xl border border-dashed border-[#232326] bg-[#161618]/35 flex items-center justify-between text-xs text-[#8A8A8E]">
                            <span className="font-medium text-[#8A8A8E]">{item.title}</span>
                            <span className="text-[#555559]">{item.subtitle}</span>
                          </div>
                        ) : (
                          <div
                            className={`p-3.5 rounded-2xl border flex items-center justify-between gap-3 transition-colors ${
                              isCompleted
                                ? 'bg-[#161618]/60 border-[#232326] opacity-65'
                                : item.type === 'fixedAnchor'
                                ? 'bg-[#161618] border-[#2FB083]/25'
                                : 'bg-[#161618] border-[#232326]'
                            }`}
                          >
                            <div className="flex items-center gap-3 min-w-0 flex-1">
                              {item.task ? (
                                <button
                                  onClick={() => handleToggleTask(item.task!)}
                                  className={`w-5 h-5 rounded-md border flex items-center justify-center shrink-0 transition-colors ${
                                    isCompleted
                                      ? 'bg-[#2FB083] border-[#2FB083] text-[#0C0C0D]'
                                      : 'border-[#555559] hover:border-[#2FB083]'
                                  }`}
                                >
                                  {isCompleted && <Check className="w-3.5 h-3.5 stroke-[2.5]" />}
                                </button>
                              ) : (
                                <Repeat className="w-4 h-4 text-[#2FB083] shrink-0" />
                              )}

                              <div className="min-w-0 flex-1">
                                <div className="flex items-center gap-2">
                                  <h4
                                    className={`text-sm font-medium truncate ${
                                      isCompleted
                                        ? 'line-through text-[#8A8A8E]'
                                        : 'text-[#F0F0F0]'
                                    }`}
                                  >
                                    {item.title}
                                  </h4>
                                  {item.isPaused && (
                                    <span className="text-[10px] font-semibold text-[#D9A441] bg-[#D9A441]/15 px-1.5 py-0.5 rounded">
                                      Checkpoint saved
                                    </span>
                                  )}
                                </div>
                                {item.subtitle && (
                                  <p className="text-xs text-[#8A8A8E] truncate mt-0.5">
                                    {item.subtitle}
                                  </p>
                                )}
                              </div>
                            </div>

                            {item.task && (
                              <button
                                onClick={() => setEditingTask(item.task!)}
                                className="text-[#555559] hover:text-[#F0F0F0] p-1 rounded"
                                title="Edit task"
                              >
                                <Edit2 className="w-3.5 h-3.5" />
                              </button>
                            )}
                          </div>
                        )}
                      </div>
                    </React.Fragment>
                  );
                })}
              </div>
            )}

            {/* Flexible Tasks (Movable work around anchors) */}
            {flexibleItems.length > 0 && (
              <div className="space-y-2 pt-3">
                <div className="flex items-center justify-between px-1">
                  <span className="text-[11px] font-semibold text-[#8A8A8E] uppercase tracking-[0.12em]">
                    Flexible Queue
                  </span>
                </div>
                {flexibleItems.map((item) => (
                  <div
                    key={item.id}
                    className="p-3.5 rounded-2xl border border-[#232326] bg-[#161618] flex items-center justify-between gap-3"
                  >
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      {item.task && (
                        <button
                          onClick={() => handleToggleTask(item.task!)}
                          className={`w-5 h-5 rounded-md border flex items-center justify-center shrink-0 transition-colors ${
                            item.isCompleted
                              ? 'bg-[#2FB083] border-[#2FB083] text-[#0C0C0D]'
                              : 'border-[#555559] hover:border-[#2FB083]'
                          }`}
                        >
                          {item.isCompleted && <Check className="w-3.5 h-3.5 stroke-[2.5]" />}
                        </button>
                      )}
                      <div className="min-w-0 flex-1">
                        <span
                          className={`text-sm font-medium block truncate ${
                            item.isCompleted ? 'line-through text-[#8A8A8E]' : 'text-[#F0F0F0]'
                          }`}
                        >
                          {item.title}
                        </span>
                        {item.subtitle && (
                          <span className="text-xs text-[#8A8A8E] block truncate mt-0.5">
                            {getCleanNotes(item.subtitle)}
                          </span>
                        )}
                      </div>
                    </div>

                    {item.task && (
                      <button
                        onClick={() => setEditingTask(item.task!)}
                        className="text-[#555559] hover:text-[#F0F0F0] p-1"
                      >
                        <Edit2 className="w-3.5 h-3.5" />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </section>

          {/* Daily Habits (Tactile rows without robotic % scoreboard) */}
          {habits.length > 0 && (
            <section className="space-y-2 pt-1">
              <div className="flex items-center justify-between px-1">
                <span className="text-[11px] font-semibold uppercase tracking-[0.12em] text-[#8A8A8E]">
                  Daily Habits
                </span>
                <span className="text-[11px] text-[#555559]">Forgiveness-first</span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                {habits.slice(0, 3).map((habit) => {
                  const checked = habitStorage.isCheckedToday(habit.id);

                  return (
                    <div
                      key={habit.id}
                      onClick={() => handleToggleHabit(habit.id)}
                      className={`flex items-center gap-3 p-3 rounded-2xl border cursor-pointer transition-all ${
                        checked
                          ? 'bg-[#2FB083]/10 border-[#2FB083]/30 text-[#8A8A8E]'
                          : 'bg-[#161618] border-[#232326] text-[#F0F0F0] hover:border-[#2FB083]/30'
                      }`}
                    >
                      <div
                        className={`w-5 h-5 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
                          checked
                            ? 'bg-[#2FB083] border-[#2FB083] text-[#0C0C0D]'
                            : 'border-[#555559]'
                        }`}
                      >
                        {checked && <Check className="w-3.5 h-3.5 stroke-[2.5]" />}
                      </div>
                      <span
                        className={`text-xs font-medium truncate ${
                          checked ? 'line-through text-[#8A8A8E]' : 'text-[#F0F0F0]'
                        }`}
                      >
                        {habit.name}
                      </span>
                    </div>
                  );
                })}
              </div>
            </section>
          )}
        </>
      )}

      {/* Capture Dialog */}
      <CaptureSheet
        isOpen={isCaptureOpen}
        onClose={() => setIsCaptureOpen(false)}
        scheduledDay={isToday ? undefined : selectedDay}
        onCreated={() => refresh()}
      />

      {/* Edit Task Dialog */}
      <TaskEditSheet
        task={editingTask}
        isOpen={!!editingTask}
        onClose={() => setEditingTask(null)}
        onUpdated={() => refresh()}
      />

      {/* Reentry Dialog */}
      <ReentryModal
        task={reentryTask}
        isOpen={!!reentryTask}
        onClose={() => setReentryTask(null)}
        onConfirm={handleConfirmReentry}
      />
    </div>
  );
};

