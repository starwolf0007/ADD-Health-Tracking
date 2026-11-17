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
import { filterNonSensitiveHabits } from './privacyGate';

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

// ---------------------------------------------------------------------------
// Account and Scoping Architecture
// ---------------------------------------------------------------------------
let storageUser: string | null = null;

export const getStorageUser = () => storageUser;

export function setStorageUser(uid: string | null) {
  const next = uid && uid.trim() && uid !== 'guest' ? uid.trim() : null;
  if (storageUser !== next) {
    storageUser = next;
    notifyStorageChange();
  }
}

export function setStorageScope(userId: string | null | undefined): void {
  setStorageUser(userId ?? null);
}

export function getStorageScope(): string {
  return storageUser || 'guest';
}

function scopedKey(key: string, user = storageUser) {
  const normalizedKey = key.startsWith('neuroflow_') ? key : `neuroflow_${key}`;
  const targetUser = user && user !== 'guest' ? user : null;
  return targetUser ? `${normalizedKey}:user:${encodeURIComponent(targetUser)}` : normalizedKey;
}

export function getScopedKey(baseKey: string, scope?: string): string {
  const targetScope = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
  return scopedKey(baseKey, targetScope);
}

export function resetCurrentLocalData() {
  Object.values(STORAGE_KEYS).forEach((key) =>
    localStorage.removeItem(scopedKey(key)),
  );
  // Pending task/note writes are retained so a local reset cannot erase unsynced work.
  notifyStorageChange();
}

// ---------------------------------------------------------------------------
// Sync Outbox and Record Definitions
// ---------------------------------------------------------------------------
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
  user = storageUser,
) {
  if (!user) return;
  const pending = readOutbox(user, collection);
  pending[id] = { revision: crypto.randomUUID(), value };
  localStorage.setItem(
    `neuroflow_outbox:${encodeURIComponent(user)}:${collection}`,
    JSON.stringify(pending),
  );
}

export interface AppSettings {
  displayName: string;
  morningBriefing: boolean;
  cloudGemini: boolean;
  autoDriveBackup?: boolean;
  lastDriveBackupAt?: number;
}

const DEFAULT_SETTINGS: AppSettings = {
  displayName: 'Bryan',
  morningBriefing: true,
  cloudGemini: false,
  autoDriveBackup: true,
};

// ---------------------------------------------------------------------------
// Reactive Change Listeners & Mutation Hooks
// ---------------------------------------------------------------------------
type StorageListener = () => void;
const listeners = new Set<StorageListener>();

export function subscribeStorage(listener: StorageListener) {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function notifyStorageChange() {
  listeners.forEach((listener) => {
    try {
      listener();
    } catch (e) {
      console.error(e);
    }
  });
}

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

export function notifyMutation(mutation: StorageMutation): void {
  mutationListeners.forEach((listener) => {
    try {
      listener(mutation);
    } catch (e) {
      console.warn('Storage mutation listener error:', e);
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function getFromStorage<T>(key: string, defaultValue: T, scope?: string): T {
  const user = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
  const k = scopedKey(key, user);
  try {
    const raw = localStorage.getItem(k);
    if (!raw) {
      localStorage.setItem(
        k,
        JSON.stringify(user && Array.isArray(defaultValue) ? [] : defaultValue),
      );
      return (user && Array.isArray(defaultValue) ? [] : defaultValue) as T;
    }
    return JSON.parse(raw) as T;
  } catch {
    return (user && Array.isArray(defaultValue) ? [] : defaultValue) as T;
  }
}

function setToStorage<T>(key: string, value: T, scope?: string): void {
  const user = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
  const k = scopedKey(key, user);
  try {
    localStorage.setItem(k, JSON.stringify(value));
    notifyStorageChange();
  } catch {
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

// ---------------------------------------------------------------------------
// Offline Queue Storage Adapter
// ---------------------------------------------------------------------------
export interface QueuedSyncOperation {
  id: string;
  type: 'task' | 'note' | 'delete_task' | 'delete_note';
  entityId: string;
  data?: any;
  timestamp: number;
}

export const offlineQueueStorage = {
  getQueue: (scope?: string): QueuedSyncOperation[] => {
    const user = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
    if (!user) return [];
    const taskOutbox = readOutbox(user, 'tasks');
    const noteOutbox = readOutbox(user, 'notes');
    const items: QueuedSyncOperation[] = [];
    for (const [id, w] of Object.entries(taskOutbox)) {
      items.push({
        id,
        type: w.value ? 'task' : 'delete_task',
        entityId: id,
        data: w.value,
        timestamp: Date.now(),
      });
    }
    for (const [id, w] of Object.entries(noteOutbox)) {
      items.push({
        id,
        type: w.value ? 'note' : 'delete_note',
        entityId: id,
        data: w.value,
        timestamp: Date.now(),
      });
    }
    return items;
  },

  enqueue: (
    op: { type: 'task' | 'delete_task' | 'note' | 'delete_note'; entityId: string; data?: any },
    scope?: string
  ): void => {
    const user = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
    if (!user) return;
    if (op.type === 'task') {
      queueWrite('tasks', op.entityId, op.data, user);
    } else if (op.type === 'delete_task') {
      queueWrite('tasks', op.entityId, null, user);
    } else if (op.type === 'note') {
      queueWrite('notes', op.entityId, op.data, user);
    } else if (op.type === 'delete_note') {
      queueWrite('notes', op.entityId, null, user);
    }
  },

  dequeue: (opId: string, scope?: string): void => {
    const user = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
    if (!user) return;
    const taskOutbox = readOutbox(user, 'tasks');
    if (taskOutbox[opId]) {
      acknowledgeWrite(user, 'tasks', opId, taskOutbox[opId].revision);
    }
    const noteOutbox = readOutbox(user, 'notes');
    if (noteOutbox[opId]) {
      acknowledgeWrite(user, 'notes', opId, noteOutbox[opId].revision);
    }
  },

  clearQueue: (_scope?: string): void => {},
};

// ---------------------------------------------------------------------------
// Storage Repositories
// ---------------------------------------------------------------------------
export const taskStorage = {
  getAll: (scope?: string): Task[] =>
    getFromStorage<Task[]>(STORAGE_KEYS.TASKS, SEED_TASKS, scope),

  getAllForScope: (scope: string): Task[] =>
    getFromStorage<Task[]>(STORAGE_KEYS.TASKS, SEED_TASKS, scope),

  save: (task: Task, isRemote: boolean = false, scope?: string): void => {
    const tasks = taskStorage.getAll(scope);
    const idx = tasks.findIndex((t) => t.id === task.id);
    if (idx >= 0) {
      tasks[idx] = task;
    } else {
      tasks.unshift(task);
    }
    setToStorage(STORAGE_KEYS.TASKS, tasks, scope);
    if (!isRemote) {
      const targetUser = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
      if (targetUser) {
        queueWrite('tasks', task.id, task, targetUser);
      }
      notifyMutation({ type: 'task_saved', task });
    }
  },

  delete: (id: string, isRemote: boolean = false, scope?: string): void => {
    const tasks = taskStorage.getAll(scope).filter((t) => t.id !== id);
    setToStorage(STORAGE_KEYS.TASKS, tasks, scope);
    if (!isRemote) {
      const targetUser = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
      if (targetUser) {
        queueWrite('tasks', id, null, targetUser);
      }
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
    getFromStorage<Routine[]>(STORAGE_KEYS.ROUTINES, SEED_ROUTINES, scope),

  getAllForScope: (scope: string): Routine[] =>
    getFromStorage<Routine[]>(STORAGE_KEYS.ROUTINES, SEED_ROUTINES, scope),

  save: (routine: Routine, scope?: string): void => {
    const routines = routineStorage.getAll(scope);
    const idx = routines.findIndex((r) => r.id === routine.id);
    if (idx >= 0) {
      routines[idx] = routine;
    } else {
      routines.push(routine);
    }
    setToStorage(STORAGE_KEYS.ROUTINES, routines, scope);
  },

  delete: (id: string, scope?: string): void => {
    const routines = routineStorage.getAll(scope).filter((r) => r.id !== id);
    setToStorage(STORAGE_KEYS.ROUTINES, routines, scope);
  },

  updateStep: (
    routineId: string,
    updatedStep: RoutineStep,
    scope?: string,
  ): void => {
    const routines = routineStorage.getAll(scope);
    const rIdx = routines.findIndex((r) => r.id === routineId);
    if (rIdx === -1) return;
    const r = routines[rIdx];
    const sIdx = r.steps.findIndex((s) => s.id === updatedStep.id);
    if (sIdx === -1) return;
    r.steps[sIdx] = updatedStep;
    routines[rIdx] = { ...r };
    setToStorage(STORAGE_KEYS.ROUTINES, routines, scope);
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
    getFromStorage<Habit[]>(STORAGE_KEYS.HABITS, SEED_HABITS, scope),

  getAllForScope: (scope: string): Habit[] =>
    getFromStorage<Habit[]>(STORAGE_KEYS.HABITS, SEED_HABITS, scope),

  save: (habit: Habit, scope?: string): void => {
    const habits = habitStorage.getAll(scope);
    const idx = habits.findIndex((h) => h.id === habit.id);
    if (idx >= 0) {
      habits[idx] = habit;
    } else {
      habits.push(habit);
    }
    setToStorage(STORAGE_KEYS.HABITS, habits, scope);
  },

  delete: (id: string, scope?: string): void => {
    const habits = habitStorage.getAll(scope).filter((h) => h.id !== id);
    setToStorage(STORAGE_KEYS.HABITS, habits, scope);
  },

  getCheckIns: (habitId?: string, scope?: string): HabitCheckIn[] => {
    const checkIns = getFromStorage<HabitCheckIn[]>(
      STORAGE_KEYS.HABIT_CHECKINS,
      [],
      scope,
    );
    return habitId ? checkIns.filter((c) => c.habitId === habitId) : checkIns;
  },

  checkIn: (habitId: string, dateStr?: string, scope?: string): void => {
    const checkIns = habitStorage.getCheckIns(undefined, scope);
    const today = dateStr || formatDateKey(new Date());
    const existing = checkIns.find(
      (c) => c.habitId === habitId && c.date === today,
    );
    if (existing) {
      existing.completed = true;
    } else {
      checkIns.push({
        id: `checkin-${Date.now()}-${habitId}`,
        habitId,
        date: today,
        completed: true,
        createdAt: new Date().toISOString(),
      });
    }
    setToStorage(STORAGE_KEYS.HABIT_CHECKINS, checkIns, scope);
  },

  uncheck: (habitId: string, dateStr?: string, scope?: string): void => {
    const checkIns = habitStorage.getCheckIns(undefined, scope);
    const today = dateStr || formatDateKey(new Date());
    const filtered = checkIns.filter(
      (c) => !(c.habitId === habitId && c.date === today),
    );
    setToStorage(STORAGE_KEYS.HABIT_CHECKINS, filtered, scope);
  },

  isCheckedToday: (habitId: string, dateStr?: string, scope?: string): boolean => {
    const today = dateStr || formatDateKey(new Date());
    return habitStorage
      .getCheckIns(undefined, scope)
      .some((c) => c.habitId === habitId && c.date === today && c.completed);
  },
};

export const moodStorage = {
  getAll: (scope?: string): MoodLog[] =>
    getFromStorage<MoodLog[]>(
      STORAGE_KEYS.MOODS,
      [
        {
          id: 'seed-mood-yesterday',
          level: 'good',
          note: 'Focused on deep work after taking morning walk',
          loggedAt: new Date(Date.now() - 86400000).toISOString(),
        },
      ],
      scope,
    ),

  getToday: (scope?: string): MoodLog | null => {
    const moods = moodStorage.getAll(scope);
    const today = formatDateKey(new Date());
    return (
      moods.find((m) => formatDateKey(new Date(m.loggedAt)) === today) || null
    );
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
    setToStorage(STORAGE_KEYS.MOODS, moods, scope);
    return entry;
  },
};

export const noteStorage = {
  getAll: (scope?: string): Note[] =>
    getFromStorage<Note[]>(
      STORAGE_KEYS.NOTES,
      [
        {
          id: 'note-1',
          body: 'Idea for evening shutdown: set timer for 8:45 PM to put phone in kitchen station.\nReduces blue light before sleep.',
          pinned: true,
          createdAt: new Date().toISOString(),
          updatedAt: new Date().toISOString(),
        },
      ],
      scope,
    ),

  getAllForScope: (scope: string): Note[] =>
    getFromStorage<Note[]>(STORAGE_KEYS.NOTES, [], scope),

  save: (note: Note, isRemote: boolean = false, scope?: string): void => {
    const notes = noteStorage.getAll(scope);
    const idx = notes.findIndex((n) => n.id === note.id);
    if (idx >= 0) {
      notes[idx] = note;
    } else {
      notes.unshift(note);
    }
    setToStorage(STORAGE_KEYS.NOTES, notes, scope);
    if (!isRemote) {
      const targetUser = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
      if (targetUser) {
        queueWrite('notes', note.id, note, targetUser);
      }
      notifyMutation({ type: 'note_saved', note });
    }
  },

  delete: (id: string, isRemote: boolean = false, scope?: string): void => {
    const notes = noteStorage.getAll(scope).filter((n) => n.id !== id);
    setToStorage(STORAGE_KEYS.NOTES, notes, scope);
    if (!isRemote) {
      const targetUser = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
      if (targetUser) {
        queueWrite('notes', id, null, targetUser);
      }
      notifyMutation({ type: 'note_deleted', noteId: id });
    }
  },

  togglePin: (id: string, scope?: string): void => {
    const notes = noteStorage.getAll(scope);
    const n = notes.find((item) => item.id === id);
    if (!n) return;
    n.pinned = !n.pinned;
    setToStorage(STORAGE_KEYS.NOTES, notes, scope);
    const targetUser = scope !== undefined ? (scope && scope !== 'guest' ? scope : null) : storageUser;
    if (targetUser) {
      queueWrite('notes', n.id, n, targetUser);
    }
    notifyMutation({ type: 'note_saved', note: n });
  },
};

export const settingsStorage = {
  get: (scope?: string): AppSettings =>
    getFromStorage<AppSettings>(
      STORAGE_KEYS.SETTINGS,
      DEFAULT_SETTINGS,
      scope,
    ),

  save: (updates: Partial<AppSettings>, scope?: string): AppSettings => {
    const current = settingsStorage.get(scope);
    const next = { ...current, ...updates };
    setToStorage(STORAGE_KEYS.SETTINGS, next, scope);
    return next;
  },
};

export const hevyStorage = {
  getWorkouts: (scope?: string): HevyWorkout[] =>
    getFromStorage<HevyWorkout[]>(
      STORAGE_KEYS.HEVY_WORKOUTS,
      SEED_WORKOUTS,
      scope,
    ),

  saveWorkouts: (workouts: HevyWorkout[], scope?: string): void => {
    setToStorage(STORAGE_KEYS.HEVY_WORKOUTS, workouts, scope);
  },

  getApiKey: (scope?: string): string => {
    return localStorage.getItem(scopedKey(STORAGE_KEYS.HEVY_KEY, scope)) || '';
  },

  saveApiKey: (key: string, scope?: string): void => {
    const k = scopedKey(STORAGE_KEYS.HEVY_KEY, scope);
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

  // 1. Snapshot backup of current guest data
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
      queueWrite('tasks', t.id, t, targetUserId);
      notifyMutation({ type: 'task_saved', task: t });
    }
  }
  setToStorage(STORAGE_KEYS.TASKS, accountTasks, targetUserId);

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
  setToStorage(STORAGE_KEYS.ROUTINES, accountRoutines, targetUserId);

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
  setToStorage(STORAGE_KEYS.HABITS, accountHabits, targetUserId);

  // 5. Non-destructive merge of notes
  const guestNotes = noteStorage.getAllForScope('guest');
  const accountNotes = noteStorage.getAll(targetUserId);
  const existingNoteIds = new Set(accountNotes.map((n) => n.id));
  let importedNotes = 0;

  for (const n of guestNotes) {
    if (!existingNoteIds.has(n.id)) {
      accountNotes.unshift(n);
      importedNotes++;
      queueWrite('notes', n.id, n, targetUserId);
      notifyMutation({ type: 'note_saved', note: n });
    }
  }
  setToStorage(STORAGE_KEYS.NOTES, accountNotes, targetUserId);

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

export interface ExportOptions {
  includeSensitive?: boolean;
}

export function exportAllData(options?: ExportOptions) {
  const includeSensitive = options?.includeSensitive === true;
  const allHabits = habitStorage.getAll();
  const exportedHabits = includeSensitive ? allHabits : filterNonSensitiveHabits(allHabits);

  return {
    version: 2,
    scope: getStorageScope(),
    privacyTier: includeSensitive ? 'full-including-sensitive' : 'standard-non-sensitive',
    exportedAt: new Date().toISOString(),
    tasks: taskStorage.getAll(),
    routines: routineStorage.getAll(),
    habits: exportedHabits,
    moods: includeSensitive ? moodStorage.getAll() : [],
    notes: noteStorage.getAll(),
    settings: settingsStorage.get(),
    hevyWorkouts: includeSensitive ? hevyStorage.getWorkouts() : [],
  };
}
