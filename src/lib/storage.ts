import { useState, useEffect, useCallback } from 'react';
import {
  Task,
  Routine,
  Habit,
  HabitCheckIn,
  MoodLog,
  MoodLevel,
  Note,
  HevyWorkout,
  RoutineStep,
} from '../types';
import {
  SEED_ROUTINES,
  SEED_HABITS,
  SEED_TASKS,
  SEED_WORKOUTS,
} from './constants';

export const STORAGE_KEYS = {
  TASKS: 'neuroflow_tasks',
  ROUTINES: 'neuroflow_routines',
  HABITS: 'neuroflow_habits',
  HABIT_CHECKINS: 'neuroflow_habit_checkins',
  MOODS: 'neuroflow_moods',
  NOTES: 'neuroflow_notes',
  SETTINGS: 'neuroflow_settings',
  HEVY_WORKOUTS: 'neuroflow_hevy_workouts',
  HEVY_KEY: 'neuroflow_hevy_api_key',
} as const;

let storageUser: string | null = null;
export const getStorageUser = () => storageUser;
export function setStorageUser(uid: string | null) {
  storageUser = uid;
  notifyStorageChange();
}
function scopedKey(key: string) {
  return storageUser ? `${key}:user:${encodeURIComponent(storageUser)}` : key;
}
export function resetCurrentLocalData() {
  Object.values(STORAGE_KEYS).forEach((key) =>
    localStorage.removeItem(scopedKey(key)),
  );
  // Pending task/note writes are retained so a local reset cannot erase unsynced work.
  notifyStorageChange();
}

export type SyncCollection = 'tasks' | 'notes';
export type SyncRecord = Task | Note;
export interface PendingWrite {
  revision: string;
  value: SyncRecord | null;
}
export function readOutbox(
  uid: string,
  collection: SyncCollection,
): Record<string, PendingWrite> {
  return JSON.parse(
    localStorage.getItem(
      `neuroflow_outbox:${encodeURIComponent(uid)}:${collection}`,
    ) || '{}',
  );
}
export function acknowledgeWrite(
  uid: string,
  collection: SyncCollection,
  id: string,
  revision: string,
) {
  const pending = readOutbox(uid, collection);
  if (pending[id]?.revision === revision) {
    delete pending[id];
    localStorage.setItem(
      `neuroflow_outbox:${encodeURIComponent(uid)}:${collection}`,
      JSON.stringify(pending),
    );
  }
}
function queueWrite(
  collection: SyncCollection,
  id: string,
  value: SyncRecord | null,
) {
  if (!storageUser) return;
  const pending = readOutbox(storageUser, collection);
  pending[id] = { revision: crypto.randomUUID(), value };
  localStorage.setItem(
    `neuroflow_outbox:${encodeURIComponent(storageUser)}:${collection}`,
    JSON.stringify(pending),
  );
}
export function subscribeStorage(listener: StorageListener) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
// Apply remote records without creating another outbound write. Pending edits win
// until acknowledged; account checks prevent a late callback entering another cache.
export function applyRemoteRecords(
  uid: string,
  collection: SyncCollection,
  records: SyncRecord[],
) {
  if (storageUser !== uid) return;
  const key = collection === 'tasks' ? STORAGE_KEYS.TASKS : STORAGE_KEYS.NOTES;
  const pending = readOutbox(uid, collection);
  const merged = new Map(records.map((record) => [record.id, record]));
  for (const [id, write] of Object.entries(pending)) {
    if (write.value) merged.set(id, write.value);
    else merged.delete(id);
  }
  setToStorage(key, [...merged.values()]);
}

export interface AppSettings {
  displayName: string;
  morningBriefing: boolean;
  cloudGemini: boolean;
}

const DEFAULT_SETTINGS: AppSettings = {
  displayName: 'Bryan',
  morningBriefing: true,
  cloudGemini: false,
};

// Simple event dispatcher for in-app reactive updates
type StorageListener = () => void;
const listeners = new Set<StorageListener>();

export function notifyStorageChange() {
  listeners.forEach((listener) => {
    try {
      listener();
    } catch (e) {
      console.error(e);
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function getFromStorage<T>(key: string, defaultValue: T): T {
  try {
    const raw = localStorage.getItem(scopedKey(key));
    if (!raw) {
      localStorage.setItem(
        scopedKey(key),
        JSON.stringify(
          storageUser && Array.isArray(defaultValue) ? [] : defaultValue,
        ),
      );
      return (
        storageUser && Array.isArray(defaultValue) ? [] : defaultValue
      ) as T;
    }
    return JSON.parse(raw) as T;
  } catch {
    return (
      storageUser && Array.isArray(defaultValue) ? [] : defaultValue
    ) as T;
  }
}

function setToStorage<T>(key: string, value: T): void {
  try {
    localStorage.setItem(scopedKey(key), JSON.stringify(value));
    notifyStorageChange();
  } catch (err) {
    throw new Error(
      'Could not save on this device. Free storage space before continuing.',
    );
  }
}

export function formatDateKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, '0');
  const d = String(date.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

export function isSameDay(d1: Date, d2: Date): boolean {
  return (
    d1.getFullYear() === d2.getFullYear() &&
    d1.getMonth() === d2.getMonth() &&
    d1.getDate() === d2.getDate()
  );
}

// ---------------------------------------------------------------------------
// Storage Repositories
// ---------------------------------------------------------------------------

export const taskStorage = {
  getAll: (): Task[] => getFromStorage<Task[]>(STORAGE_KEYS.TASKS, SEED_TASKS),

  save: (task: Task): void => {
    const tasks = taskStorage.getAll();
    const idx = tasks.findIndex((t) => t.id === task.id);
    if (idx >= 0) {
      tasks[idx] = task;
    } else {
      tasks.unshift(task);
    }
    queueWrite('tasks', task.id, task);
    setToStorage(STORAGE_KEYS.TASKS, tasks);
  },

  delete: (id: string): void => {
    queueWrite('tasks', id, null);
    const tasks = taskStorage.getAll().filter((t) => t.id !== id);
    setToStorage(STORAGE_KEYS.TASKS, tasks);
  },

  complete: (id: string): Task | null => {
    const tasks = taskStorage.getAll();
    const task = tasks.find((t) => t.id === id);
    if (!task) return null;
    const updated: Task = {
      ...task,
      status: 'completed',
      completedAt: new Date().toISOString(),
    };
    taskStorage.save(updated);
    return updated;
  },

  toggleStatus: (id: string): Task | null => {
    const tasks = taskStorage.getAll();
    const task = tasks.find((t) => t.id === id);
    if (!task) return null;
    const isComp = task.status === 'completed';
    const updated: Task = {
      ...task,
      status: isComp ? 'pending' : 'completed',
      completedAt: isComp ? undefined : new Date().toISOString(),
    };
    taskStorage.save(updated);
    return updated;
  },

  startTask: (id: string): Task | null => {
    const tasks = taskStorage.getAll();
    const task = tasks.find((t) => t.id === id);
    if (!task) return null;
    const updated: Task = {
      ...task,
      status: 'inProgress',
      activeStartedAt: new Date().toISOString(),
    };
    taskStorage.save(updated);
    return updated;
  },

  pauseTask: (id: string, nextAction?: string): Task | null => {
    const tasks = taskStorage.getAll();
    const task = tasks.find((t) => t.id === id);
    if (!task) return null;
    const updated: Task = {
      ...task,
      status: 'paused',
      reentryNote: {
        lastCompletedStep: 'Paused for context switch',
        nextAction: nextAction || 'Open task and take first physical step',
        updatedAt: new Date().toISOString(),
      },
    };
    taskStorage.save(updated);
    return updated;
  },
};

export const routineStorage = {
  getAll: (): Routine[] =>
    getFromStorage<Routine[]>(STORAGE_KEYS.ROUTINES, SEED_ROUTINES),

  save: (routine: Routine): void => {
    const routines = routineStorage.getAll();
    const idx = routines.findIndex((r) => r.id === routine.id);
    if (idx >= 0) {
      routines[idx] = routine;
    } else {
      routines.push(routine);
    }
    setToStorage(STORAGE_KEYS.ROUTINES, routines);
  },

  delete: (id: string): void => {
    const routines = routineStorage.getAll().filter((r) => r.id !== id);
    setToStorage(STORAGE_KEYS.ROUTINES, routines);
  },

  updateStep: (routineId: string, updatedStep: RoutineStep): void => {
    const routines = routineStorage.getAll();
    const rIdx = routines.findIndex((r) => r.id === routineId);
    if (rIdx === -1) return;
    const r = routines[rIdx];
    const sIdx = r.steps.findIndex((s) => s.id === updatedStep.id);
    if (sIdx === -1) return;
    r.steps[sIdx] = updatedStep;
    routines[rIdx] = { ...r };
    setToStorage(STORAGE_KEYS.ROUTINES, routines);
  },

  resetRoutineSteps: (routineId: string): void => {
    const routines = routineStorage.getAll();
    const r = routines.find((item) => item.id === routineId);
    if (!r) return;
    r.steps = r.steps.map((s) => ({ ...s, isComplete: false }));
    routineStorage.save(r);
  },
};

export const habitStorage = {
  getAll: (): Habit[] =>
    getFromStorage<Habit[]>(STORAGE_KEYS.HABITS, SEED_HABITS),

  save: (habit: Habit): void => {
    const habits = habitStorage.getAll();
    const idx = habits.findIndex((h) => h.id === habit.id);
    if (idx >= 0) {
      habits[idx] = habit;
    } else {
      habits.push(habit);
    }
    setToStorage(STORAGE_KEYS.HABITS, habits);
  },

  delete: (id: string): void => {
    const habits = habitStorage.getAll().filter((h) => h.id !== id);
    setToStorage(STORAGE_KEYS.HABITS, habits);
  },

  getCheckIns: (habitId?: string): HabitCheckIn[] => {
    const checkIns = getFromStorage<HabitCheckIn[]>(
      STORAGE_KEYS.HABIT_CHECKINS,
      [],
    );
    return habitId ? checkIns.filter((c) => c.habitId === habitId) : checkIns;
  },

  checkIn: (habitId: string, dateStr?: string): void => {
    const checkIns = habitStorage.getCheckIns();
    const today = dateStr || formatDateKey(new Date());
    const existing = checkIns.find(
      (c) => c.habitId === habitId && c.date === today,
    );
    if (existing) {
      existing.completed = true;
    } else {
      checkIns.push({
        id: `checkin-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
        habitId,
        date: today,
        completed: true,
        createdAt: new Date().toISOString(),
      });
    }
    setToStorage(STORAGE_KEYS.HABIT_CHECKINS, checkIns);
  },

  uncheck: (habitId: string, dateStr?: string): void => {
    const checkIns = habitStorage.getCheckIns();
    const today = dateStr || formatDateKey(new Date());
    const filtered = checkIns.filter(
      (c) => !(c.habitId === habitId && c.date === today),
    );
    setToStorage(STORAGE_KEYS.HABIT_CHECKINS, filtered);
  },

  isCheckedToday: (habitId: string, dateStr?: string): boolean => {
    const today = dateStr || formatDateKey(new Date());
    return habitStorage
      .getCheckIns()
      .some((c) => c.habitId === habitId && c.date === today && c.completed);
  },

  getCompletionRate30d: (habit: Habit): number => {
    const checkIns = habitStorage.getCheckIns(habit.id);
    const now = new Date();
    let applicable = 0;
    let completed = 0;

    for (let i = 0; i < 30; i++) {
      const d = new Date(now.getTime() - i * 86400000);
      const dayKey = formatDateKey(d);
      const weekday = d.getDay(); // 0 is Sunday, 1 is Monday ... 6 is Saturday
      const isWeekday = weekday >= 1 && weekday <= 5;
      const isWeekend = weekday === 0 || weekday === 6;

      let applies = true;
      if (habit.frequency === 'weekdays' && !isWeekday) applies = false;
      if (habit.frequency === 'weekends' && !isWeekend) applies = false;

      if (applies) {
        applicable++;
        if (checkIns.some((c) => c.date === dayKey && c.completed)) {
          completed++;
        }
      }
    }

    if (applicable === 0) return 0;
    return completed / applicable;
  },

  getSkipsRemainingThisMonth: (habit: Habit): number => {
    const checkIns = habitStorage.getCheckIns(habit.id);
    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    let misses = 0;
    const monthlyBudget = 5;

    for (let d = new Date(startOfMonth); d <= now; d.setDate(d.getDate() + 1)) {
      const dayKey = formatDateKey(d);
      const weekday = d.getDay();
      const isWeekday = weekday >= 1 && weekday <= 5;
      const isWeekend = weekday === 0 || weekday === 6;

      let applies = true;
      if (habit.frequency === 'weekdays' && !isWeekday) applies = false;
      if (habit.frequency === 'weekends' && !isWeekend) applies = false;

      if (applies) {
        const hit = checkIns.some((c) => c.date === dayKey && c.completed);
        if (!hit) misses++;
      }
    }

    const remaining = monthlyBudget - misses;
    return remaining < 0 ? 0 : remaining;
  },
};

export const moodStorage = {
  getAll: (): MoodLog[] =>
    getFromStorage<MoodLog[]>(STORAGE_KEYS.MOODS, [
      {
        id: 'seed-mood-yesterday',
        level: 'good',
        note: 'Solid morning focus after good sleep',
        loggedAt: new Date(Date.now() - 86400000).toISOString(),
      },
    ]),

  getToday: (): MoodLog | null => {
    const moods = moodStorage.getAll();
    const today = formatDateKey(new Date());
    return (
      moods.find((m) => formatDateKey(new Date(m.loggedAt)) === today) || null
    );
  },

  log: (level: MoodLevel, note?: string): MoodLog => {
    const moods = moodStorage.getAll();
    const entry: MoodLog = {
      id: `mood-${Date.now()}`,
      level,
      note,
      loggedAt: new Date().toISOString(),
    };
    moods.unshift(entry);
    setToStorage(STORAGE_KEYS.MOODS, moods);
    return entry;
  },
};

export const noteStorage = {
  getAll: (): Note[] =>
    getFromStorage<Note[]>(STORAGE_KEYS.NOTES, [
      {
        id: 'note-1',
        body: 'Idea for evening shutdown: set timer for 8:45 PM to put phone in kitchen station.\nReduces blue light before sleep.',
        pinned: true,
        createdAt: new Date(Date.now() - 3600000 * 5).toISOString(),
        updatedAt: new Date(Date.now() - 3600000 * 5).toISOString(),
      },
      {
        id: 'note-2',
        body: 'Grocery list for weekend:\n- Greek yogurt\n- Bananas\n- Cold brew beans\n- Almond milk',
        pinned: false,
        createdAt: new Date(Date.now() - 86400000).toISOString(),
        updatedAt: new Date(Date.now() - 86400000).toISOString(),
      },
    ]),

  save: (note: Note): void => {
    const notes = noteStorage.getAll();
    const idx = notes.findIndex((n) => n.id === note.id);
    if (idx >= 0) {
      notes[idx] = note;
    } else {
      notes.unshift(note);
    }
    queueWrite('notes', note.id, note);
    setToStorage(STORAGE_KEYS.NOTES, notes);
  },

  delete: (id: string): void => {
    queueWrite('notes', id, null);
    const notes = noteStorage.getAll().filter((n) => n.id !== id);
    setToStorage(STORAGE_KEYS.NOTES, notes);
  },

  togglePin: (id: string): void => {
    const notes = noteStorage.getAll();
    const n = notes.find((item) => item.id === id);
    if (!n) return;
    n.pinned = !n.pinned;
    queueWrite('notes', n.id, n);
    setToStorage(STORAGE_KEYS.NOTES, notes);
  },
};

export const settingsStorage = {
  get: (): AppSettings =>
    getFromStorage<AppSettings>(STORAGE_KEYS.SETTINGS, DEFAULT_SETTINGS),

  save: (updates: Partial<AppSettings>): AppSettings => {
    const current = settingsStorage.get();
    const next = { ...current, ...updates };
    setToStorage(STORAGE_KEYS.SETTINGS, next);
    return next;
  },
};

export const hevyStorage = {
  getWorkouts: (): HevyWorkout[] =>
    getFromStorage<HevyWorkout[]>(STORAGE_KEYS.HEVY_WORKOUTS, SEED_WORKOUTS),

  saveWorkouts: (workouts: HevyWorkout[]): void => {
    setToStorage(STORAGE_KEYS.HEVY_WORKOUTS, workouts);
  },

  getApiKey: (): string => {
    return localStorage.getItem(scopedKey(STORAGE_KEYS.HEVY_KEY)) || '';
  },

  saveApiKey: (key: string): void => {
    if (key) {
      localStorage.setItem(scopedKey(STORAGE_KEYS.HEVY_KEY), key);
    } else {
      localStorage.removeItem(scopedKey(STORAGE_KEYS.HEVY_KEY));
    }
    notifyStorageChange();
  },
};

// ---------------------------------------------------------------------------
// Reactive React Hook
// ---------------------------------------------------------------------------
export function useNeuroStorage() {
  const [version, setVersion] = useState(0);

  useEffect(() => {
    const onChange = () => setVersion((v) => v + 1);
    listeners.add(onChange);
    return () => {
      listeners.delete(onChange);
    };
  }, []);

  const refresh = useCallback(() => {
    setVersion((v) => v + 1);
  }, []);

  return {
    version,
    refresh,
    tasks: taskStorage.getAll(),
    routines: routineStorage.getAll(),
    habits: habitStorage.getAll(),
    todayMood: moodStorage.getToday(),
    recentMoods: moodStorage.getAll(),
    notes: noteStorage.getAll(),
    settings: settingsStorage.get(),
    hevyWorkouts: hevyStorage.getWorkouts(),
    hevyApiKey: hevyStorage.getApiKey(),
  };
}
