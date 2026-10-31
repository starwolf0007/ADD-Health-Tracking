import React, { useState } from 'react';
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
  Plus,
  ArrowRight,
  MoreVertical,
  Edit2,
  Trash2,
  Clock,
  BatteryLow,
  BatteryMedium,
  Battery,
} from 'lucide-react';
import { Task, TimelineItem, Routine, Habit, Achievement } from '../types';
import {
  isSameDay,
  formatDateKey,
  taskStorage,
  habitStorage,
} from '../lib/storage';
import {
  Executive,
  DaySummary,
  buildTimeline,
  getTimelineItemPhase,
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

export const TodayScreen: React.FC<TodayScreenProps> = ({
  tasks,
  routines,
  habits,
  todayMood,
  onOpenLexi,
  onOpenSettings,
  onLaunchRoutine,
  onTriggerAchievement,
  onOpenVisualTimer,
  refresh,
}) => {
  const [selectedDay, setSelectedDay] = useState<Date>(new Date());
  const [isCaptureOpen, setIsCaptureOpen] = useState(false);
  const [editingTask, setEditingTask] = useState<Task | null>(null);
  const [reentryTask, setReentryTask] = useState<Task | null>(null);

  const isToday = isSameDay(selectedDay, new Date());
  const pendingTasks = tasks.filter((t) => t.status !== 'completed');

  // Executive evaluation: automatically swaps mode based on today's mood
  const currentMoodLevel = isToday ? todayMood?.level : null;
  const plan = Executive.evaluate(pendingTasks, currentMoodLevel);
  const isQuickWins = isToday && plan.mode === 'quickWins' && plan.quickWins.length > 0;

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

  const handleToggleTask = (task: Task) => {
    const wasPaused = task.status === 'paused';
    const updated = taskStorage.toggleStatus(task.id);
    if (updated && updated.status === 'completed' && wasPaused) {
      onTriggerAchievement({
        id: `reentry-${Date.now()}`,
        title: 'RE-ENTRY COMPLETE',
        message: 'Resumed and finished a paused task without guilt!',
        type: 'reentry',
        timestamp: Date.now(),
      });
    }
    refresh();
  };

  const handleStartTask = (task: Task) => {
    taskStorage.startTask(task.id);
    refresh();
  };

  const handlePauseTask = (task: Task) => {
    setReentryTask(task);
  };

  const handleConfirmReentry = (lastStep: string, nextAction: string) => {
    if (!reentryTask) return;
    const updated: Task = {
      ...reentryTask,
      status: 'paused',
      reentryNote: {
        lastCompletedStep: lastStep || 'Paused for context shift',
        nextAction: nextAction || 'Open task and take first physical step',
        updatedAt: new Date().toISOString(),
      },
    };
    taskStorage.save(updated);
    refresh();
  };

  const handleToggleHabit = (habitId: string) => {
    if (habitStorage.isCheckedToday(habitId)) {
      habitStorage.uncheck(habitId);
    } else {
      habitStorage.checkIn(habitId);
    }
    refresh();
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

  return (
    <div className="pb-28 max-w-2xl mx-auto px-4 pt-3 space-y-4">
      {/* Date Navigator */}
      <div className="flex items-center justify-between bg-[#1C1C1F]/80 backdrop-blur border border-[#232326] rounded-full px-2 py-1 shadow-sm">
        <button
          onClick={handlePrevDay}
          className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-full transition-colors"
          title="Previous day"
        >
          <ChevronLeft className="w-5 h-5" />
        </button>

        <div className="text-center">
          <span className="text-xs font-semibold text-[#F0F0F0]">
            {isToday ? 'Today · ' : ''}
            {selectedDay.toLocaleDateString(undefined, {
              weekday: 'short',
              month: 'short',
              day: 'numeric',
            })}
          </span>
        </div>

        <div className="flex items-center gap-1">
          {!isToday && (
            <button
              onClick={handleGoToToday}
              className="text-[11px] font-medium text-[#2FB083] px-2.5 py-0.5 rounded-full bg-[#2FB083]/10 hover:bg-[#2FB083]/20 transition-colors"
            >
              Back to Today
            </button>
          )}
          <button
            onClick={handleNextDay}
            className="p-1.5 text-[#8A8A8E] hover:text-[#F0F0F0] rounded-full transition-colors"
            title="Next day"
          >
            <ChevronRight className="w-5 h-5" />
          </button>
        </div>
      </div>

      {/* Day Summary Card (with Lexi) */}
      <div
        onClick={onOpenLexi}
        className="bg-[#1C1C1F]/90 border border-[#232326] rounded-2xl p-4 shadow-lg cursor-pointer hover:border-[#2FB083]/40 transition-all flex items-center gap-3.5"
      >
        <LexiAvatar size={46} visualState={isQuickWins ? 'evening' : 'idle'} />
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between">
            <span className="text-[11px] font-semibold tracking-wider text-[#2FB083] uppercase">
              A calm look ahead
            </span>
            <span className="text-[11px] text-[#555559]">Tap to talk with Lexi</span>
          </div>
          <p className="text-sm text-[#F0F0F0] mt-1 font-normal leading-snug">
            {DaySummary.build(timelineItems)}
          </p>
          {plan.reason && isToday && (
            <p className="text-xs text-[#2FB083] mt-1 flex items-center gap-1 font-medium">
              <Sparkles className="w-3 h-3 shrink-0" />
              <span>{plan.reason}</span>
            </p>
          )}
        </div>
      </div>

      {/* Visual Clock Timer Quick Bar (ADHD Time-Blindness Support) */}
      {isToday && onOpenVisualTimer && (
        <div className="bg-[#161618] border border-[#232326] rounded-2xl p-3.5 shadow-sm flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-xl bg-[#2FB083]/15 text-[#2FB083]">
              <Clock className="w-4 h-4" />
            </div>
            <div>
              <h4 className="text-xs font-semibold text-[#F0F0F0]">Visual Clock Timer</h4>
              <p className="text-[11px] text-[#8A8A8E]">See time move as you work</p>
            </div>
          </div>
          <div className="flex items-center gap-1.5">
            <button
              onClick={() => onOpenVisualTimer(plan.primaryTask, 5)}
              className="px-2.5 py-1 rounded-lg bg-[#1C1C1F] hover:bg-[#2FB083]/20 hover:text-[#2FB083] text-[11px] font-semibold text-[#8A8A8E] border border-[#232326] transition-colors"
            >
              5m
            </button>
            <button
              onClick={() => onOpenVisualTimer(plan.primaryTask, 25)}
              className="px-2.5 py-1 rounded-lg bg-[#2FB083]/20 text-[#2FB083] border border-[#2FB083]/40 text-[11px] font-semibold transition-colors"
            >
              25m
            </button>
            <button
              onClick={() => onOpenVisualTimer(plan.primaryTask, 50)}
              className="px-2.5 py-1 rounded-lg bg-[#1C1C1F] hover:bg-[#2FB083]/20 hover:text-[#2FB083] text-[11px] font-semibold text-[#8A8A8E] border border-[#232326] transition-colors"
            >
              50m
            </button>
          </div>
        </div>
      )}

      {/* Due Routines Card (if any active routines exist for today) */}
      {isToday && routines.length > 0 && (
        <div className="bg-[#161618] border border-[#232326] rounded-2xl p-4 shadow-sm">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <Repeat className="w-4 h-4 text-[#2FB083]" />
              <span className="text-xs font-semibold uppercase tracking-wider text-[#8A8A8E]">
                Today's Routines
              </span>
            </div>
            <span className="text-xs text-[#555559]">
              {routines.filter((r) => r.steps.every((s) => s.isComplete)).length}/
              {routines.length} completed
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
                  className="flex items-center justify-between p-3 rounded-xl bg-[#1C1C1F] hover:bg-[#212124] border border-[#232326] cursor-pointer transition-colors"
                >
                  <div>
                    <h4
                      className={`text-sm font-medium ${
                        isAllDone ? 'line-through text-[#8A8A8E]' : 'text-[#F0F0F0]'
                      }`}
                    >
                      {routine.name}
                    </h4>
                    <p className="text-xs text-[#8A8A8E] mt-0.5">
                      {routine.anchor.toUpperCase()} · {completedCount}/{totalCount} steps
                    </p>
                  </div>
                  <div className="flex items-center gap-2">
                    <span
                      className={`text-xs px-2.5 py-1 rounded-lg font-mono ${
                        isAllDone
                          ? 'bg-[#2FB083]/15 text-[#2FB083]'
                          : 'bg-[#232326] text-[#8A8A8E]'
                      }`}
                    >
                      {isAllDone ? 'Done' : 'Launch'}
                    </span>
                    <ArrowRight className="w-4 h-4 text-[#555559]" />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* QUICK WINS MODE (Auto-swapped if mood is rough/low per spec §6) */}
      {isQuickWins ? (
        <div className="bg-[#1C1C1F] border border-[#2FB083]/30 rounded-2xl p-5 shadow-xl space-y-3">
          <div className="flex items-center gap-2">
            <div className="w-6 h-6 rounded-full bg-[#2FB083]/20 flex items-center justify-center">
              <Zap className="w-3.5 h-3.5 text-[#2FB083]" />
            </div>
            <h3 className="text-sm font-semibold tracking-wider text-[#2FB083] uppercase">
              Quick Wins
            </h3>
          </div>

          <p className="text-xs text-[#8A8A8E] leading-relaxed">
            A lighter shape for today. Tap a win to mark it done.{' '}
            <span className="text-[#F0F0F0] font-medium">Nothing else is tracked today.</span>
          </p>

          <div className="space-y-2 pt-1">
            {plan.quickWins.map((task) => (
              <div
                key={task.id}
                onClick={() => handleToggleTask(task)}
                className="flex items-center gap-3 p-3.5 rounded-xl bg-[#161618] border border-[#232326] hover:border-[#2FB083]/40 cursor-pointer transition-colors"
              >
                <div className="text-[#2FB083] shrink-0">
                  <Circle className="w-5 h-5" />
                </div>
                <div className="flex-1 min-w-0">
                  <span className="text-sm text-[#F0F0F0] font-medium leading-snug block truncate">
                    {task.title}
                  </span>
                  {task.notes && (
                    <span className="text-xs text-[#8A8A8E] block truncate mt-0.5">
                      {task.notes}
                    </span>
                  )}
                </div>
                <span className="text-[10px] uppercase font-mono px-2 py-0.5 rounded bg-[#2FB083]/10 text-[#2FB083]">
                  {task.estimatedMinutes ? `${task.estimatedMinutes}m` : 'Quick'}
                </span>
              </div>
            ))}
          </div>

          {fixedItems.length > 0 && (
            <div className="pt-3 border-t border-[#232326] space-y-2">
              <h4 className="text-xs font-semibold text-[#8A8A8E] uppercase tracking-wider">
                Still fixed today
              </h4>
              {fixedItems.map((item) => (
                <div
                  key={item.id}
                  className="flex items-center justify-between p-2.5 rounded-lg bg-[#161618] text-xs text-[#8A8A8E]"
                >
                  <span className="font-medium text-[#F0F0F0]">{item.title}</span>
                  <span>{item.subtitle}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      ) : (
        /* STANDARD MODE */
        <>
          {/* Active Recommended Task Card */}
          {plan.primaryTask && isToday && (
            <div
              className={`bg-[#1C1C1F] rounded-2xl p-4 border transition-all shadow-md ${
                plan.primaryTask.status === 'inProgress'
                  ? 'border-[#2FB083] shadow-[#2FB083]/10'
                  : 'border-[#232326]'
              }`}
            >
              <div className="flex items-center justify-between mb-2">
                <span className="text-[11px] font-semibold uppercase tracking-wider text-[#2FB083] flex items-center gap-1.5">
                  <Sparkles className="w-3.5 h-3.5" />
                  Recommended Next Step
                </span>
                <span className="text-xs font-mono text-[#8A8A8E] uppercase">
                  {plan.primaryTask.energy} energy
                </span>
              </div>

              <h3 className="text-base font-medium text-[#F0F0F0] mb-1">
                {plan.primaryTask.title}
              </h3>
              {plan.primaryTask.notes && (
                <p className="text-xs text-[#8A8A8E] mb-3 leading-relaxed">
                  {plan.primaryTask.notes}
                </p>
              )}

              {/* If paused, show reentry note */}
              {plan.primaryTask.status === 'paused' && plan.primaryTask.reentryNote && (
                <div className="bg-[#D9A441]/10 border border-[#D9A441]/25 rounded-xl p-2.5 mb-3 text-xs">
                  <div className="font-semibold text-[#D9A441] mb-0.5">
                    Return point preserved:
                  </div>
                  <div className="text-[#F0F0F0]">
                    {plan.primaryTask.reentryNote.nextAction || 'Open task to resume'}
                  </div>
                </div>
              )}

              {/* Action Buttons */}
              <div className="flex items-center gap-2 pt-1">
                {plan.primaryTask.status !== 'inProgress' ? (
                  <button
                    onClick={() => handleStartTask(plan.primaryTask!)}
                    className="flex-1 py-2 px-3 bg-[#2FB083] hover:bg-[#2FB083]/90 text-[#0C0C0D] rounded-xl text-xs font-semibold flex items-center justify-center gap-1.5 transition-colors"
                  >
                    <Play className="w-3.5 h-3.5 fill-current" />
                    <span>Start Focus</span>
                  </button>
                ) : (
                  <button
                    onClick={() => handlePauseTask(plan.primaryTask!)}
                    className="flex-1 py-2 px-3 bg-[#212124] hover:bg-[#28282C] text-[#D9A441] border border-[#D9A441]/30 rounded-xl text-xs font-semibold flex items-center justify-center gap-1.5 transition-colors"
                  >
                    <Pause className="w-3.5 h-3.5" />
                    <span>Pause & Return Later</span>
                  </button>
                )}

                {onOpenVisualTimer && (
                  <button
                    onClick={() => onOpenVisualTimer(plan.primaryTask)}
                    className="py-2 px-3 bg-[#161618] hover:bg-[#212124] text-[#2FB083] border border-[#2FB083]/30 rounded-xl text-xs font-semibold flex items-center justify-center gap-1.5 transition-colors"
                    title="Open moving visual clock timer"
                  >
                    <Clock className="w-3.5 h-3.5" />
                    <span>Clock</span>
                  </button>
                )}

                <button
                  onClick={() => handleToggleTask(plan.primaryTask!)}
                  className="py-2 px-3.5 bg-[#161618] hover:bg-[#212124] text-[#F0F0F0] border border-[#232326] rounded-xl text-xs font-medium flex items-center gap-1.5 transition-colors"
                >
                  <CheckCircle2 className="w-4 h-4 text-[#2FB083]" />
                  <span>Done</span>
                </button>
              </div>
            </div>
          )}

          {/* Habits Section (Capped at 3 daily habits) */}
          {habits.length > 0 && (
            <div className="bg-[#161618] border border-[#232326] rounded-2xl p-3.5 shadow-sm space-y-2">
              <div className="flex items-center justify-between px-1">
                <span className="text-[11px] font-semibold uppercase tracking-wider text-[#8A8A8E]">
                  Daily Habits
                </span>
                <span className="text-[11px] text-[#555559]">30d momentum</span>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
                {habits.slice(0, 3).map((habit) => {
                  const checked = habitStorage.isCheckedToday(habit.id);
                  const rate = Math.round(habitStorage.getCompletionRate30d(habit) * 100);

                  return (
                    <div
                      key={habit.id}
                      onClick={() => handleToggleHabit(habit.id)}
                      className={`flex items-center gap-2.5 p-2.5 rounded-xl border cursor-pointer transition-all ${
                        checked
                          ? 'bg-[#2FB083]/10 border-[#2FB083]/30 text-[#8A8A8E]'
                          : 'bg-[#1C1C1F] border-[#232326] text-[#F0F0F0] hover:border-[#2FB083]/30'
                      }`}
                    >
                      <div
                        className={`w-5 h-5 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
                          checked
                            ? 'bg-[#2FB083] border-[#2FB083] text-[#0C0C0D]'
                            : 'border-[#555559]'
                        }`}
                      >
                        {checked && <CheckCircle2 className="w-3.5 h-3.5 fill-current" />}
                      </div>
                      <div className="flex-1 min-w-0">
                        <span
                          className={`text-xs font-medium block truncate ${
                            checked ? 'line-through text-[#8A8A8E]' : 'text-[#F0F0F0]'
                          }`}
                        >
                          {habit.name}
                        </span>
                        <span className="text-[10px] text-[#555559] block font-mono">
                          {rate}% completion
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* Timeline Schedule for Selected Day */}
          <div className="space-y-3 pt-2">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-semibold tracking-wider text-[#8A8A8E] uppercase">
                {isToday ? 'Your Day' : 'Day Schedule'}
              </h3>
            </div>

            {dayItems.length === 0 ? (
              <div className="p-6 text-center border border-dashed border-[#232326] rounded-2xl text-xs text-[#8A8A8E]">
                Nothing scheduled yet for this day.
              </div>
            ) : (
              <div className="space-y-2 relative">
                {dayItems.map((item, index) => {
                  const isCurrent = isToday && index === markerIndex;
                  const isCompleted = item.isCompleted;

                  return (
                    <React.Fragment key={item.id}>
                      {/* Current Time Marker */}
                      {isCurrent && (
                        <div className="flex items-center gap-2 py-1">
                          <span className="text-[11px] font-mono font-medium text-[#2FB083]">
                            {now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </span>
                          <span className="w-2 h-2 rounded-full bg-[#2FB083] shadow-sm shadow-[#2FB083]/50" />
                          <div className="flex-1 h-px bg-[#2FB083]/40" />
                          <span className="text-[10px] font-bold text-[#2FB083] tracking-wider uppercase">
                            NOW
                          </span>
                        </div>
                      )}

                      {/* Timeline Card */}
                      {item.type === 'openSpace' ? (
                        <div className="p-2.5 rounded-xl border border-dashed border-[#232326] bg-[#161618]/40 text-center text-xs text-[#555559]">
                          {item.title} · {item.subtitle}
                        </div>
                      ) : (
                        <div
                          className={`p-3.5 rounded-xl border flex items-center justify-between gap-3 transition-colors ${
                            isCompleted
                              ? 'bg-[#161618] border-[#232326] opacity-60'
                              : item.type === 'fixedAnchor'
                              ? 'bg-[#1C1C1F] border-[#2FB083]/20'
                              : 'bg-[#1C1C1F] border-[#232326]'
                          }`}
                        >
                          <div className="flex items-center gap-3 min-w-0 flex-1">
                            {item.task ? (
                              <button
                                onClick={() => handleToggleTask(item.task!)}
                                className={`w-5 h-5 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
                                  isCompleted
                                    ? 'bg-[#2FB083] border-[#2FB083] text-[#0C0C0D]'
                                    : 'border-[#555559] hover:border-[#2FB083]'
                                }`}
                              >
                                {isCompleted && <CheckCircle2 className="w-3.5 h-3.5 fill-current" />}
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
                                    Paused
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

                          <div className="flex items-center gap-2 shrink-0">
                            {item.start && (
                              <span className="text-xs font-mono text-[#8A8A8E]">
                                {new Date(item.start).toLocaleTimeString([], {
                                  hour: '2-digit',
                                  minute: '2-digit',
                                })}
                              </span>
                            )}
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
                        </div>
                      )}
                    </React.Fragment>
                  );
                })}
              </div>
            )}

            {/* Flexible tasks (not tied to specific hour) */}
            {flexibleItems.length > 0 && (
              <div className="space-y-2 pt-4">
                <h4 className="text-xs font-semibold text-[#8A8A8E] uppercase tracking-wider">
                  Flexible Tasks
                </h4>
                {flexibleItems.map((item) => (
                  <div
                    key={item.id}
                    className="p-3.5 rounded-xl border border-[#232326] bg-[#161618] flex items-center justify-between gap-3"
                  >
                    <div className="flex items-center gap-3 min-w-0 flex-1">
                      {item.task && (
                        <button
                          onClick={() => handleToggleTask(item.task!)}
                          className={`w-5 h-5 rounded-full border flex items-center justify-center shrink-0 transition-colors ${
                            item.isCompleted
                              ? 'bg-[#2FB083] border-[#2FB083] text-[#0C0C0D]'
                              : 'border-[#555559] hover:border-[#2FB083]'
                          }`}
                        >
                          {item.isCompleted && (
                            <CheckCircle2 className="w-3.5 h-3.5 fill-current" />
                          )}
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
                            {item.subtitle}
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
          </div>
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
