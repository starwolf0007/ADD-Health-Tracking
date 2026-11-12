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

    // Normal mode: Prioritize inProgress or paused tasks first (optimize for the moment of return),
    // then surface lowest energy pending task
    const sorted = [...allPending].sort((a, b) => {
      const statusWeight = (s: Task['status']) =>
        s === 'inProgress' ? 0 : s === 'paused' ? 1 : 2;
      const swDiff = statusWeight(a.status) - statusWeight(b.status);
      if (swDiff !== 0) return swDiff;

      const energyOrder: Record<string, number> = { low: 0, medium: 1, high: 2 };
      return energyOrder[a.energy] - energyOrder[b.energy];
    });

    return {
      mode: 'normal',
      primaryTask: sorted[0],
      quickWins: [],
      reason:
        sorted[0]?.status === 'paused'
          ? 'Saved checkpoint ready — pick right back up where you stopped.'
          : 'Lowest lift first — momentum beats order.',
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

export interface InlineMicroStep {
  id: string;
  title: string;
  minutes: number;
  done: boolean;
}

/**
 * Deterministically extracts or generates 3 concrete, physical micro-steps (2–5m each)
 * for inline "Make it smaller" task slicing on TodayScreen without requiring a tab hop or AI call.
 */
export function sliceTaskIntoMicroSteps(task: Task): InlineMicroStep[] {
  // 1. Check if task.notes already has markdown checklist lines (- [ ] or - [x])
  if (task.notes) {
    const lines = task.notes.split('\n');
    const parsed: InlineMicroStep[] = [];
    lines.forEach((line, idx) => {
      const match = line.match(/^\s*-\s*\[([ xX])\]\s*(.+)$/);
      if (match) {
        const done = match[1].toLowerCase() === 'x';
        const rawTitle = match[2].replace(/\(\d+m\)\s*$/, '').trim();
        const minMatch = match[2].match(/\((\d+)m\)/);
        parsed.push({
          id: `${task.id}-step-${idx}`,
          title: rawTitle,
          minutes: minMatch ? Number(minMatch[1]) : 3,
          done,
        });
      }
    });
    if (parsed.length > 0) {
      return parsed;
    }
  }

  const lower = task.title.toLowerCase();
  if (lower.includes('laundry') || lower.includes('shirt') || lower.includes('clothes')) {
    return [
      { id: `${task.id}-s1`, title: 'Bring the basket beside the dresser', minutes: 2, done: false },
      { id: `${task.id}-s2`, title: 'Put 5 shirts away (hangers or drawer)', minutes: 3, done: false },
      { id: `${task.id}-s3`, title: 'Toss socks & small items into top drawer', minutes: 3, done: false },
    ];
  }
  if (lower.includes('reply') || lower.includes('email') || lower.includes('text') || lower.includes('call') || lower.includes('landlord')) {
    return [
      { id: `${task.id}-s1`, title: 'Open the thread and read the last message', minutes: 1, done: false },
      { id: `${task.id}-s2`, title: 'Draft a 1-sentence reply (no overthinking)', minutes: 2, done: false },
      { id: `${task.id}-s3`, title: 'Hit send and close the window', minutes: 1, done: false },
    ];
  }
  if (lower.includes('petg') || lower.includes('print') || lower.includes('filament') || lower.includes('order')) {
    return [
      { id: `${task.id}-s1`, title: 'Check current spool color & 1.75mm spec', minutes: 2, done: false },
      { id: `${task.id}-s2`, title: 'Add 1 spool to cart & confirm delivery day', minutes: 2, done: false },
      { id: `${task.id}-s3`, title: 'Place order and archive receipt', minutes: 1, done: false },
    ];
  }
  if (lower.includes('review') || lower.includes('focus') || lower.includes('align') || lower.includes('plan')) {
    return [
      { id: `${task.id}-s1`, title: 'Pick the single most important outcome for today', minutes: 3, done: false },
      { id: `${task.id}-s2`, title: 'Park everything else in flexible tasks', minutes: 3, done: false },
      { id: `${task.id}-s3`, title: 'Start a 5-minute timer on step one', minutes: 5, done: false },
    ];
  }

  const totalEst = task.estimatedMinutes ?? 15;
  const stepMin = Math.max(2, Math.min(5, Math.round(totalEst / 3)));
  return [
    {
      id: `${task.id}-s1`,
      title: `Set up workspace & open what you need for "${task.title}"`,
      minutes: 2,
      done: false,
    },
    {
      id: `${task.id}-s2`,
      title: task.notes ? `First pass: ${task.notes}` : `Complete the first 5-minute physical chunk`,
      minutes: stepMin,
      done: false,
    },
    {
      id: `${task.id}-s3`,
      title: 'Wrap up or save a quick return point',
      minutes: 2,
      done: false,
    },
  ];
}

export class DaySummary {
  static build(items: TimelineItem[]): string {
    const remaining = items.filter((item) => !item.isCompleted && item.type !== 'openSpace');
    const completed = items.filter((item) => item.isCompleted && item.type !== 'openSpace').length;
    const anchors = remaining.filter((item) => item.type === 'fixedAnchor').length;
    const flexible = remaining.filter(
      (item) => item.type === 'flexibleBlock' || item.type === 'task'
    ).length;

    if (anchors === 0 && flexible === 0) {
      return completed > 0
        ? `All clear — ${completed} ${completed === 1 ? 'item' : 'items'} wrapped up today.`
        : 'Wide-open runway today. Pick one small win whenever you want to start.';
    }

    const parts: string[] = [];
    if (anchors > 0) {
      parts.push(`${anchors} fixed ${anchors === 1 ? 'anchor' : 'anchors'}`);
    }
    if (flexible > 0) {
      parts.push(`${flexible} flexible ${flexible === 1 ? 'step' : 'steps'}`);
    }
    const suffix = completed > 0 ? ` · ${completed} already done` : '';
    return `${parts.join(' and ')} ahead${suffix}.`;
  }

  /**
   * Builds a warm, first-person contextual Lexi cue aligned with LEXI_MASTER_CANON.md
   * (peer-level, concise, schedule-aware, zero coaching clichés, works 100% offline).
   */
  static buildLexiCue(
    items: TimelineItem[],
    primaryTask: Task | undefined,
    isQuickWins: boolean,
    now: Date = new Date()
  ): string {
    const hour = now.getHours();
    const isWeekday = now.getDay() >= 1 && now.getDay() <= 5;

    if (isQuickWins) {
      return "We're running light today. Pick one 5-minute win below and ignore the rest—no scorekeeping.";
    }

    // Bedtime protocol awareness (after 21:30 / 22:00 per Canon)
    if (hour >= 22) {
      return "It's past 10:00 PM—your 5:00 AM wake target is coming up. Park whatever's left with a checkpoint and call it a night.";
    }
    if (hour >= 21 && hour < 22) {
      return "Evening wind-down window. Let's wrap the current thread cleanly or save a return point for tomorrow.";
    }

    if (primaryTask?.status === 'paused' && primaryTask.reentryNote) {
      return `I kept your spot on "${primaryTask.title}". Next physical move: ${
        primaryTask.reentryNote.nextAction || 'take the first 2-minute step'
      }.`;
    }

    if (primaryTask?.status === 'inProgress') {
      return `You're mid-flight on "${primaryTask.title}". Stay with this single step—or tap Pause & Park if life interrupted.`;
    }

    if (isWeekday && hour >= 6 && hour < 14) {
      return primaryTask
        ? `Shift hours. Keep it simple—"${primaryTask.title}" is queued up next whenever you have a clean window.`
        : 'Shift window is rolling. Catch quick thoughts into Notes and keep your runway clear.';
    }

    if (primaryTask) {
      const mins = primaryTask.estimatedMinutes ?? 10;
      return `Don't overthink the whole list. Start with "${primaryTask.title}" (~${mins}m)—or tap "Make it smaller" and I'll slice it into 3 tiny moves.`;
    }

    return DaySummary.build(items);
  }
}

export function formatBreathingRoomDuration(gapMins: number, nextTitle?: string): string {
  const hours = Math.floor(gapMins / 60);
  const mins = gapMins % 60;
  let durationLabel = '';
  if (hours >= 4) {
    durationLabel = 'Open afternoon margin';
  } else if (hours > 0 && mins > 0) {
    durationLabel = `${hours}h ${mins}m open buffer`;
  } else if (hours > 0) {
    durationLabel = `${hours}h open buffer`;
  } else {
    durationLabel = `${mins}m transition buffer`;
  }
  return nextTitle ? `${durationLabel} before ${nextTitle}` : `${durationLabel} — unscheduled margin`;
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
        ? `Completed all ${routine.steps.length} steps ✓`
        : `${completedCount} of ${routine.steps.length} steps done`,
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
        subtitle: task.notes || (task.energy ? `${task.energy} energy` : undefined),
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

  // 4. Insert calm breathing room for gaps >= 45 minutes
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
            title: 'Breathing room',
            subtitle: formatBreathingRoomDuration(gapMins, item.title),
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

