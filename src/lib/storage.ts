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
import { SEED_ROUTINES, SEED_HABITS, SEED_TASKS, SEED_WORKOUTS } from './constants';

// ---------------------------------------------------------------------------
// Storage Scope Management
// ---------------------------------------------------------------------------
let currentScopeId = 'guest';

export function setStorageScope(userId: string | null | undefined): void {
  const nextScope = userId && userId.trim() ? userId.trim() : 'guest';
  if (currentScopeId !== nextScope) {
    currentScopeId = nextScope;
    notifyStorageChange();
  }
}

export function getStorageScope(): string {
  return currentScopeId;
}

export function getScopedKey(baseKey: string, scope?: string): string {
  const s = scope || currentScopeId;
  return `neuroflow_${s}_${baseKey}`;
}

export interface AppSettings {
  displayName: string;
  morningBriefing: boolean;
  cloudGemini: boolean;
  autoDriveBackup: boolean;
}

const DEFAULT_SETTINGS: AppSettings = {
  displayName: 'Bryan',
  morningBriefing: true,
  cloudGemini: false,
  autoDriveBackup: true,
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

// Mutation notifications for Firestore sync engine
export type StorageMutation =
  | { type: 'task_saved'; task: Task }
  | { type: 'task_deleted'; taskId: string }
  | { type: 'note_saved'; note: Note }
  | { type: 'note_deleted'; noteId: string };

type MutationListener = (mutation: StorageMutation) => void;
const mutationListeners = new Set<MutationListener>();

export function registerMutationListener(fn: MutationListener): () => void {
  mutationListeners.add(fn);
  return () => {
    mutationListeners.delete(fn);
  };
}

function notifyMutation(mutation: StorageMutation) {
  mutationListeners.forEach((listener) => {
    try {
      listener(mutation);
    } catch (e) {
      console.error('Storage mutation listener error:', e);
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function getFromStorage<T>(key: string, defaultValue: T): T {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) {
      localStorage.setItem(key, JSON.stringify(defaultValue));
      return defaultValue;
    }
    return JSON.parse(raw) as T;
  } catch {
    return defaultValue;
  }
}

function setToStorage<T>(key: string, value: T): void {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    notifyStorageChange();
  } catch (err) {
    console.error('Failed to save to localStorage:', err);
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
// Automatic Pre-Migration Safety Backup & Legacy Key Migration
// ---------------------------------------------------------------------------
const LEGACY_KEYS = [
  'neuroflow_tasks',
  'neuroflow_routines',
  'neuroflow_habits',
  'neuroflow_habit_checkins',
  'neuroflow_moods',
  'neuroflow_notes',
  'neuroflow_settings',
  'neuroflow_hevy_workouts',
  'neuroflow_hevy_api_key',
];

function runLegacyMigration() {
  if (typeof window === 'undefined' || !window.localStorage) return;

  try {
    // 1. Create untouchable safety backup if not already present
    const backupKey = 'neuroflow_pre_migration_backup';
    if (!localStorage.getItem(backupKey)) {
      const snapshot: Record<string, string | null> = {};
      for (const k of LEGACY_KEYS) {
        snapshot[k] = localStorage.getItem(k);
      }
      localStorage.setItem(
        backupKey,
        JSON.stringify({
          createdAt: new Date().toISOString(),
          version: '1.0.0-pre-scoped',
          data: snapshot,
        })
      );
    }

    // 2. Migrate legacy keys to guest scope if guest scope does not exist yet
    const keyMap: Record<string, string> = {
      neuroflow_tasks: 'neuroflow_guest_tasks',
      neuroflow_routines: 'neuroflow_guest_routines',
      neuroflow_habits: 'neuroflow_guest_habits',
      neuroflow_habit_checkins: 'neuroflow_guest_habit_checkins',
      neuroflow_moods: 'neuroflow_guest_moods',
      neuroflow_notes: 'neuroflow_guest_notes',
      neuroflow_settings: 'neuroflow_guest_settings',
      neuroflow_hevy_workouts: 'neuroflow_guest_hevy_workouts',
      neuroflow_hevy_api_key: 'neuroflow_guest_hevy_api_key',
    };

    for (const [legacy, guest] of Object.entries(keyMap)) {
      const val = localStorage.getItem(legacy);
      if (val && !localStorage.getItem(guest)) {
        localStorage.setItem(guest, val);
      }
    }
  } catch (err) {
    console.error('Safe legacy migration encountered error:', err);
  }
}

// Run safely on initialization
runLegacyMigration();

// ---------------------------------------------------------------------------
// Offline Firestore Sync Queue
// ---------------------------------------------------------------------------
export interface QueuedSyncOperation {
  id: string;
  type: 'task' | 'note' | 'delete_task' | 'delete_note';
  entityId: string;
  data?: any;
  timestamp: number;
  retryCount: number;
}

export const offlineQueueStorage = {
  getQueue: (scope?: string): QueuedSyncOperation[] =>
    getFromStorage<QueuedSyncOperation[]>(getScopedKey('offline_queue', scope), []),

  enqueue: (
    op: Omit<QueuedSyncOperation, 'id' | 'timestamp' | 'retryCount'>,
    scope?: string
  ): void => {
    const queue = offlineQueueStorage.getQueue(scope);
    const existingIdx = queue.findIndex(
      (item) => item.entityId === op.entityId && item.type === op.type
    );
    const newOp: QueuedSyncOperation = {
      ...op,
      id: `sync-${Date.now()}-${Math.random().toString(36).slice(2, 6)}`,
      timestamp: Date.now(),
      retryCount: 0,
    };
    if (existingIdx >= 0) {
      queue[existingIdx] = newOp;
    } else {
      queue.push(newOp);
    }
    setToStorage(getScopedKey('offline_queue', scope), queue);
  },

  dequeue: (opId: string, scope?: string): void => {
    const queue = offlineQueueStorage
      .getQueue(scope)
      .filter((item) => item.id !== opId);
    setToStorage(getScopedKey('offline_queue', scope), queue);
  },

  clearQueue: (scope?: string): void => {
    setToStorage(getScopedKey('offline_queue', scope), []);
  },
};

// ---------------------------------------------------------------------------
// Storage Repositories (User-Scoped)
// ---------------------------------------------------------------------------

export const taskStorage = {
  getAll: (scope?: string): Task[] =>
    getFromStorage<Task[]>(getScopedKey('tasks', scope), SEED_TASKS),

  getAllForScope: (scope: string): Task[] =>
    getFromStorage<Task[]>(getScopedKey('tasks', scope), SEED_TASKS),

  save: (task: Task, isRemote: boolean = false, scope?: string): void => {
    const tasks = taskStorage.getAll(scope);
    const idx = tasks.findIndex((t) => t.id === task.id);
    if (idx >= 0) {
      tasks[idx] = task;
    } else {
      tasks.unshift(task);
    }
    setToStorage(getScopedKey('tasks', scope), tasks);
    if (!isRemote) {
      notifyMutation({ type: 'task_saved', task });
    }
  },

  delete: (id: string, isRemote: boolean = false, scope?: string): void => {
    const tasks = taskStorage.getAll(scope).filter((t) => t.id !== id);
    setToStorage(getScopedKey('tasks', scope), tasks);
    if (!isRemote) {
      notifyMutation({ type: 'task_deleted', taskId: id });
    }
  },

  complete: (id: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const task = tasks.find((t) => t.id === id);
    if (!task) return null;
    const updated: Task = {
      ...task,
      status: 'completed',
      completedAt: new Date().toISOString(),
    };
    taskStorage.save(updated, false, scope);
    return updated;
  },

  toggleStatus: (id: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const task = tasks.find((t) => t.id === id);
    if (!task) return null;
    const isComp = task.status === 'completed';
    const updated: Task = {
      ...task,
      status: isComp ? 'pending' : 'completed',
      completedAt: isComp ? undefined : new Date().toISOString(),
    };
    taskStorage.save(updated, false, scope);
    return updated;
  },

  startTask: (id: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const task = tasks.find((t) => t.id === id);
    if (!task) return null;
    const updated: Task = {
      ...task,
      status: 'inProgress',
      activeStartedAt: new Date().toISOString(),
    };
    taskStorage.save(updated, false, scope);
    return updated;
  },

  pauseTask: (id: string, nextAction?: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
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
    taskStorage.save(updated, false, scope);
    return updated;
  },
};

export const routineStorage = {
  getAll: (scope?: string): Routine[] =>
    getFromStorage<Routine[]>(getScopedKey('routines', scope), SEED_ROUTINES),

  getAllForScope: (scope: string): Routine[] =>
    getFromStorage<Routine[]>(getScopedKey('routines', scope), SEED_ROUTINES),

  save: (routine: Routine, scope?: string): void => {
    const routines = routineStorage.getAll(scope);
    const idx = routines.findIndex((r) => r.id === routine.id);
    if (idx >= 0) {
      routines[idx] = routine;
    } else {
      routines.push(routine);
    }
    setToStorage(getScopedKey('routines', scope), routines);
  },

  delete: (id: string, scope?: string): void => {
    const routines = routineStorage.getAll(scope).filter((r) => r.id !== id);
    setToStorage(getScopedKey('routines', scope), routines);
  },

  updateStep: (routineId: string, updatedStep: RoutineStep, scope?: string): void => {
    const routines = routineStorage.getAll(scope);
    const rIdx = routines.findIndex((r) => r.id === routineId);
    if (rIdx === -1) return;
    const r = routines[rIdx];
    const sIdx = r.steps.findIndex((s) => s.id === updatedStep.id);
    if (sIdx === -1) return;
    r.steps[sIdx] = updatedStep;
    routines[rIdx] = { ...r };
    setToStorage(getScopedKey('routines', scope), routines);
  },

  resetRoutineSteps: (routineId: string, scope?: string): void => {
    const routines = routineStorage.getAll(scope);
    const r = routines.find((item) => item.id === routineId);
    if (!r) return;
    r.steps = r.steps.map((s) => ({ ...s, isComplete: false }));
    routineStorage.save(r, scope);
  },
};

export const habitStorage = {
  getAll: (scope?: string): Habit[] =>
    getFromStorage<Habit[]>(getScopedKey('habits', scope), SEED_HABITS),

  getAllForScope: (scope: string): Habit[] =>
    getFromStorage<Habit[]>(getScopedKey('habits', scope), SEED_HABITS),

  save: (habit: Habit, scope?: string): void => {
    const habits = habitStorage.getAll(scope);
    const idx = habits.findIndex((h) => h.id === habit.id);
    if (idx >= 0) {
      habits[idx] = habit;
    } else {
      habits.push(habit);
    }
    setToStorage(getScopedKey('habits', scope), habits);
  },

  delete: (id: string, scope?: string): void => {
    const habits = habitStorage.getAll(scope).filter((h) => h.id !== id);
    setToStorage(getScopedKey('habits', scope), habits);
  },

  getCheckIns: (habitId?: string, scope?: string): HabitCheckIn[] => {
    const checkIns = getFromStorage<HabitCheckIn[]>(
      getScopedKey('habit_checkins', scope),
      []
    );
    return habitId ? checkIns.filter((c) => c.habitId === habitId) : checkIns;
  },

  checkIn: (habitId: string, dateStr?: string, scope?: string): void => {
    const checkIns = habitStorage.getCheckIns(undefined, scope);
    const today = dateStr || formatDateKey(new Date());
    const existing = checkIns.find((c) => c.habitId === habitId && c.date === today);
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
    setToStorage(getScopedKey('habit_checkins', scope), checkIns);
  },

  uncheck: (habitId: string, dateStr?: string, scope?: string): void => {
    const checkIns = habitStorage.getCheckIns(undefined, scope);
    const today = dateStr || formatDateKey(new Date());
    const filtered = checkIns.filter((c) => !(c.habitId === habitId && c.date === today));
    setToStorage(getScopedKey('habit_checkins', scope), filtered);
  },

  isCheckedToday: (habitId: string, dateStr?: string, scope?: string): boolean => {
    const today = dateStr || formatDateKey(new Date());
    return habitStorage
      .getCheckIns(undefined, scope)
      .some((c) => c.habitId === habitId && c.date === today && c.completed);
  },

  getCompletionRate30d: (habit: Habit, scope?: string): number => {
    const checkIns = habitStorage.getCheckIns(habit.id, scope);
    const now = new Date();
    let applicable = 0;
    let completed = 0;

    for (let i = 0; i < 30; i++) {
      const d = new Date(now.getTime() - i * 86400000);
      const dayKey = formatDateKey(d);
      const weekday = d.getDay();
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

  getSkipsRemainingThisMonth: (habit: Habit, scope?: string): number => {
    const checkIns = habitStorage.getCheckIns(habit.id, scope);
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
  getAll: (scope?: string): MoodLog[] =>
    getFromStorage<MoodLog[]>(getScopedKey('moods', scope), [
      {
        id: 'seed-mood-yesterday',
        level: 'good',
        note: 'Solid morning focus after good sleep',
        loggedAt: new Date(Date.now() - 86400000).toISOString(),
      },
    ]),

  getToday: (scope?: string): MoodLog | null => {
    const moods = moodStorage.getAll(scope);
    const today = formatDateKey(new Date());
    return moods.find((m) => formatDateKey(new Date(m.loggedAt)) === today) || null;
  },

  log: (level: MoodLevel, note?: string, scope?: string): MoodLog => {
    const moods = moodStorage.getAll(scope);
    const entry: MoodLog = {
      id: `mood-${Date.now()}`,
      level,
      note,
      loggedAt: new Date().toISOString(),
    };
    moods.unshift(entry);
    setToStorage(getScopedKey('moods', scope), moods);
    return entry;
  },
};

export const noteStorage = {
  getAll: (scope?: string): Note[] =>
    getFromStorage<Note[]>(getScopedKey('notes', scope), [
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

  getAllForScope: (scope: string): Note[] =>
    getFromStorage<Note[]>(getScopedKey('notes', scope), []),

  save: (note: Note, isRemote: boolean = false, scope?: string): void => {
    const notes = noteStorage.getAll(scope);
    const idx = notes.findIndex((n) => n.id === note.id);
    if (idx >= 0) {
      notes[idx] = note;
    } else {
      notes.unshift(note);
    }
    setToStorage(getScopedKey('notes', scope), notes);
    if (!isRemote) {
      notifyMutation({ type: 'note_saved', note });
    }
  },

  delete: (id: string, isRemote: boolean = false, scope?: string): void => {
    const notes = noteStorage.getAll(scope).filter((n) => n.id !== id);
    setToStorage(getScopedKey('notes', scope), notes);
    if (!isRemote) {
      notifyMutation({ type: 'note_deleted', noteId: id });
    }
  },

  togglePin: (id: string, scope?: string): void => {
    const notes = noteStorage.getAll(scope);
    const n = notes.find((item) => item.id === id);
    if (!n) return;
    n.pinned = !n.pinned;
    setToStorage(getScopedKey('notes', scope), notes);
  },
};

export const settingsStorage = {
  get: (scope?: string): AppSettings =>
    getFromStorage<AppSettings>(getScopedKey('settings', scope), DEFAULT_SETTINGS),

  save: (updates: Partial<AppSettings>, scope?: string): AppSettings => {
    const current = settingsStorage.get(scope);
    const next = { ...current, ...updates };
    setToStorage(getScopedKey('settings', scope), next);
    return next;
  },
};

export const hevyStorage = {
  getWorkouts: (scope?: string): HevyWorkout[] =>
    getFromStorage<HevyWorkout[]>(
      getScopedKey('hevy_workouts', scope),
      SEED_WORKOUTS
    ),

  saveWorkouts: (workouts: HevyWorkout[], scope?: string): void => {
    setToStorage(getScopedKey('hevy_workouts', scope), workouts);
  },

  getApiKey: (scope?: string): string => {
    return localStorage.getItem(getScopedKey('hevy_api_key', scope)) || '';
  },

  saveApiKey: (key: string, scope?: string): void => {
    const k = getScopedKey('hevy_api_key', scope);
    if (key) {
      localStorage.setItem(k, key);
    } else {
      localStorage.removeItem(k);
    }
    notifyStorageChange();
  },
};

// ---------------------------------------------------------------------------
// Guest Data Import & Non-Destructive Migration API
// ---------------------------------------------------------------------------

export interface GuestDataSummary {
  taskCount: number;
  routineCount: number;
  habitCount: number;
  noteCount: number;
  hasData: boolean;
}

export function getGuestDataSummary(): GuestDataSummary {
  try {
    const tasks = taskStorage.getAllForScope('guest');
    const routines = routineStorage.getAllForScope('guest');
    const habits = habitStorage.getAllForScope('guest');
    const notes = noteStorage.getAllForScope('guest');

    const taskCount = tasks.length;
    const routineCount = routines.length;
    const habitCount = habits.length;
    const noteCount = notes.length;

    return {
      taskCount,
      routineCount,
      habitCount,
      noteCount,
      hasData: taskCount > 0 || routineCount > 0 || habitCount > 0 || noteCount > 0,
    };
  } catch {
    return { taskCount: 0, routineCount: 0, habitCount: 0, noteCount: 0, hasData: false };
  }
}

export function isGuestImportResolved(userId: string): boolean {
  if (!userId) return true;
  return localStorage.getItem(`neuroflow_${userId}_guest_import_resolved`) === 'true';
}

export function setGuestImportResolved(userId: string, resolved: boolean): void {
  if (!userId) return;
  if (resolved) {
    localStorage.setItem(`neuroflow_${userId}_guest_import_resolved`, 'true');
  } else {
    localStorage.removeItem(`neuroflow_${userId}_guest_import_resolved`);
  }
}

export function importGuestDataToAccount(targetUserId: string): {
  importedTasks: number;
  importedRoutines: number;
  importedHabits: number;
  importedNotes: number;
} {
  if (!targetUserId || targetUserId === 'guest') {
    return { importedTasks: 0, importedRoutines: 0, importedHabits: 0, importedNotes: 0 };
  }

  // 1. Create a snapshot backup of current guest data before import
  const guestBackupKey = `neuroflow_guest_backup_after_import_${Date.now()}`;
  const guestSnapshot = {
    exportedAt: new Date().toISOString(),
    tasks: taskStorage.getAllForScope('guest'),
    routines: routineStorage.getAllForScope('guest'),
    habits: habitStorage.getAllForScope('guest'),
    habitCheckIns: habitStorage.getCheckIns(undefined, 'guest'),
    moods: moodStorage.getAll('guest'),
    notes: noteStorage.getAllForScope('guest'),
  };
  localStorage.setItem(guestBackupKey, JSON.stringify(guestSnapshot));

  // 2. Non-destructive merge of tasks
  const guestTasks = taskStorage.getAllForScope('guest');
  const accountTasks = taskStorage.getAll(targetUserId);
  const existingTaskIds = new Set(accountTasks.map((t) => t.id));
  let importedTasks = 0;

  for (const t of guestTasks) {
    if (!existingTaskIds.has(t.id)) {
      accountTasks.unshift(t);
      importedTasks++;
      // Notify mutation so it syncs to user's Firestore
      notifyMutation({ type: 'task_saved', task: t });
    }
  }
  setToStorage(getScopedKey('tasks', targetUserId), accountTasks);

  // 3. Non-destructive merge of routines
  const guestRoutines = routineStorage.getAllForScope('guest');
  const accountRoutines = routineStorage.getAll(targetUserId);
  const existingRoutineIds = new Set(accountRoutines.map((r) => r.id));
  let importedRoutines = 0;

  for (const r of guestRoutines) {
    if (!existingRoutineIds.has(r.id)) {
      accountRoutines.push(r);
      importedRoutines++;
    }
  }
  setToStorage(getScopedKey('routines', targetUserId), accountRoutines);

  // 4. Non-destructive merge of habits
  const guestHabits = habitStorage.getAllForScope('guest');
  const accountHabits = habitStorage.getAll(targetUserId);
  const existingHabitIds = new Set(accountHabits.map((h) => h.id));
  let importedHabits = 0;

  for (const h of guestHabits) {
    if (!existingHabitIds.has(h.id)) {
      accountHabits.push(h);
      importedHabits++;
    }
  }
  setToStorage(getScopedKey('habits', targetUserId), accountHabits);

  // 5. Non-destructive merge of notes
  const guestNotes = noteStorage.getAllForScope('guest');
  const accountNotes = noteStorage.getAll(targetUserId);
  const existingNoteIds = new Set(accountNotes.map((n) => n.id));
  let importedNotes = 0;

  for (const n of guestNotes) {
    if (!existingNoteIds.has(n.id)) {
      accountNotes.unshift(n);
      importedNotes++;
      notifyMutation({ type: 'note_saved', note: n });
    }
  }
  setToStorage(getScopedKey('notes', targetUserId), accountNotes);

  // Mark import as resolved for this account
  setGuestImportResolved(targetUserId, true);

  // Notify listeners to update views
  notifyStorageChange();

  return { importedTasks, importedRoutines, importedHabits, importedNotes };
}

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
    currentScope: getStorageScope(),
    tasks: taskStorage.getAll(),
    routines: routineStorage.getAll(),
    habits: habitStorage.getAll(),
    todayMood: moodStorage.getToday(),
    recentMoods: moodStorage.getAll(),
    notes: noteStorage.getAll(),
    settings: settingsStorage.get(),
    hevyWorkouts: hevyStorage.getWorkouts(),
    hevyApiKey: hevyStorage.getApiKey(),
    offlineQueue: offlineQueueStorage.getQueue(),
  };
}

export function exportAllData() {
  return {
    version: 2,
    scope: getStorageScope(),
    exportedAt: new Date().toISOString(),
    tasks: taskStorage.getAll(),
    routines: routineStorage.getAll(),
    habits: habitStorage.getAll(),
    moods: moodStorage.getAll(),
    notes: noteStorage.getAll(),
    settings: settingsStorage.get(),
    hevyWorkouts: hevyStorage.getWorkouts(),
  };
}
