import {
  Task,
  Routine,
  MoodLevel,
  DayMode,
  Plan,
  TimelineItem,
  TimelinePhase,
} from '../types';
import { isSameDay } from './storage';

export const MOOD_META: Record<
  MoodLevel,
  { label: string; score: number; triggersQuickWins: boolean }
> = {
  veryLow: { label: 'Rough', score: 1, triggersQuickWins: true },
  low: { label: 'Low', score: 2, triggersQuickWins: true },
  neutral: { label: 'Okay', score: 3, triggersQuickWins: false },
  good: { label: 'Good', score: 4, triggersQuickWins: false },
  great: { label: 'Great', score: 5, triggersQuickWins: false },
};

export class Executive {
  static evaluate(
    allPending: Task[],
    latestMood?: MoodLevel | null
  ): Plan {
    if (allPending.length === 0) {
      return {
        mode: 'normal',
        primaryTask: undefined,
        quickWins: [],
        reason: 'All clear — nothing pending.',
      };
    }

    const indicatesLighterDay = latestMood ? MOOD_META[latestMood].triggersQuickWins : false;

    if (indicatesLighterDay) {
      const quickWins = this.selectQuickWins(allPending);
      return {
        mode: 'quickWins',
        quickWins,
        reason: 'Lighter load today — showing your easiest wins first.',
      };
    }

    // Normal mode: Surface lowest energy / highest priority pending task first
    const sorted = [...allPending].sort((a, b) => {
      const energyOrder: Record<string, number> = { low: 0, medium: 1, high: 2 };
      return energyOrder[a.energy] - energyOrder[b.energy];
    });

    return {
      mode: 'normal',
      primaryTask: sorted[0],
      quickWins: [],
      reason: '',
    };
  }

  static selectQuickWins(pending: Task[]): Task[] {
    // Spec §6 locked invariant: max 3 items
    // First, tasks tagged isQuickWin or low-energy
    const lowEnergy = pending.filter((t) => t.isQuickWin || t.energy === 'low');
    const sortedCandidates = [...lowEnergy].sort((a, b) => {
      const estA = a.estimatedMinutes ?? 10;
      const estB = b.estimatedMinutes ?? 10;
      return estA - estB;
    });

    if (sortedCandidates.length >= 1) {
      return sortedCandidates.slice(0, 3);
    }

    // If no low energy task, pick the lowest effort tasks capped at 3
    const sortedAll = [...pending].sort((a, b) => {
      const estA = a.estimatedMinutes ?? 15;
      const estB = b.estimatedMinutes ?? 15;
      return estA - estB;
    });

    return sortedAll.slice(0, 3);
  }
}

export class DaySummary {
  static build(items: TimelineItem[]): string {
    const remaining = items.filter((item) => !item.isCompleted);
    const anchors = remaining.filter((item) => item.type === 'fixedAnchor').length;
    const flexible = remaining.filter((item) => item.type === 'flexibleBlock').length;

    if (anchors === 0 && flexible === 0) {
      return items.length === 0
        ? 'Your day is open. Add one gentle next step when you are ready.'
        : 'Your planned anchors and flexible blocks are clear.';
    }
    if (anchors === 0) {
      return `You have ${flexible === 1 ? 'one flexible block' : `${flexible} flexible blocks`} left.`;
    }
    if (flexible === 0) {
      return `You have ${anchors === 1 ? 'one anchor' : `${anchors} anchors`} left.`;
    }
    return `You have ${anchors === 1 ? 'one anchor' : `${anchors} anchors`} and ${
      flexible === 1 ? 'one flexible block' : `${flexible} flexible blocks`
    } left.`;
  }
}

export function getTimelineItemPhase(item: TimelineItem, now: Date): TimelinePhase {
  if (item.isCompleted) return 'past';
  if (item.end && new Date(item.end) <= now) return 'past';
  if (item.start && new Date(item.start) <= now && (!item.end || new Date(item.end) > now)) {
    return 'current';
  }
  return 'upcoming';
}

export function buildTimeline(
  day: Date,
  tasks: Task[],
  routines: Routine[]
): TimelineItem[] {
  const items: TimelineItem[] = [];

  // 1. Add routines that fire on this day
  const dayWeekday = day.getDay() === 0 ? 7 : day.getDay(); // 1=Mon...7=Sun
  for (const routine of routines) {
    if (!routine.isActive) continue;
    if (routine.activeDays && !routine.activeDays.includes(String(dayWeekday))) {
      continue;
    }

    let hour = routine.scheduleHour;
    if (hour === undefined) {
      switch (routine.anchor) {
        case 'morning':
          hour = 8;
          break;
        case 'midday':
          hour = 12;
          break;
        case 'evening':
          hour = 18;
          break;
        case 'custom':
        default:
          hour = 9;
          break;
      }
    }
    const minute = routine.scheduleMinute ?? 0;
    const start = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hour, minute);
    const durationMins = routine.steps.reduce(
      (sum, s) => sum + (s.durationMinutes ?? 5),
      0
    );
    const end = new Date(start.getTime() + Math.max(15, Math.min(90, durationMins)) * 60000);

    const isComplete = routine.steps.length > 0 && routine.steps.every((s) => s.isComplete);
    const completedCount = routine.steps.filter((s) => s.isComplete).length;

    items.push({
      id: `routine-${routine.id}`,
      type: 'fixedAnchor',
      title: routine.name,
      subtitle: isComplete
        ? 'Complete'
        : `${completedCount}/${routine.steps.length} steps`,
      start: start.toISOString(),
      end: end.toISOString(),
      isCompleted: isComplete,
    });
  }

  // 2. Add tasks for this day (tasks with dueDate on this day, or flexible tasks if day is today)
  for (const task of tasks) {
    if (task.status === 'completed' && task.completedAt) {
      const compDate = new Date(task.completedAt);
      if (!isSameDay(compDate, day)) continue;
    }

    if (task.dueDate) {
      const dueDate = new Date(task.dueDate);
      if (isSameDay(dueDate, day)) {
        const start = dueDate;
        const end = new Date(start.getTime() + (task.estimatedMinutes ?? 30) * 60000);
        items.push({
          id: `task-${task.id}`,
          type: 'task',
          title: task.title,
          subtitle: task.notes,
          start: start.toISOString(),
          end: end.toISOString(),
          task,
          isCompleted: task.status === 'completed',
          isPaused: task.status === 'paused',
        });
      }
    } else if (isSameDay(day, new Date())) {
      // Flexible task without fixed time
      items.push({
        id: `task-${task.id}`,
        type: 'flexibleBlock',
        title: task.title,
        subtitle: task.notes || (task.energy ? `${task.energy.toUpperCase()} energy` : undefined),
        task,
        isCompleted: task.status === 'completed',
        isPaused: task.status === 'paused',
      });
    }
  }

  // 3. Sort items chronologically
  items.sort((a, b) => {
    if (!a.start && !b.start) return a.id.localeCompare(b.id);
    if (!a.start) return 1;
    if (!b.start) return -1;
    return new Date(a.start).getTime() - new Date(b.start).getTime();
  });

  // 4. Insert open spaces for gaps >= 45 minutes
  const timedItems = items.filter((i) => i.start && i.end);
  const result: TimelineItem[] = [];

  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (result.length > 0 && item.start) {
      const prev = result[result.length - 1];
      if (prev.end) {
        const prevEndMs = new Date(prev.end).getTime();
        const currStartMs = new Date(item.start).getTime();
        const gapMins = Math.round((currStartMs - prevEndMs) / 60000);
        if (gapMins >= 45) {
          result.push({
            id: `space-${prevEndMs}`,
            type: 'openSpace',
            title: 'Open space',
            subtitle: `${gapMins} minutes with no plan`,
            start: prev.end,
            end: item.start,
          });
        }
      }
    }
    result.push(item);
  }

  return result;
}
