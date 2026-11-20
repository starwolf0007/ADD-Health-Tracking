import { useState, useEffect, useCallback } from "react";
import {
  Task,
  TaskStatus,
  LockedTaskStatus,
  Routine,
  Habit,
  HabitCheckIn,
  MoodLog,
  MoodLevel,
  Note,
  HevyWorkout,
  RoutineStep,
  ReentryNote,
  MicroStepItem,
} from "../types";
import { AlertService } from "./alerts";
import {
  SEED_ROUTINES,
  SEED_HABITS,
  SEED_TASKS,
  SEED_WORKOUTS,
} from "./constants";
import { filterNonSensitiveHabits } from "./privacyGate";

export const STORAGE_KEYS = {
  TASKS: "neuroflow_tasks",
  ROUTINES: "neuroflow_routines",
  HABITS: "neuroflow_habits",
  HABIT_CHECKINS: "neuroflow_habit_checkins",
  MOODS: "neuroflow_moods",
  NOTES: "neuroflow_notes",
  SETTINGS: "neuroflow_settings",
  HEVY_WORKOUTS: "neuroflow_hevy_workouts",
  HEVY_KEY: "neuroflow_hevy_api_key",
} as const;

// ---------------------------------------------------------------------------
// Account and Scoping Architecture
// ---------------------------------------------------------------------------
let storageUser: string | null = null;

export const getStorageUser = () => storageUser;

export function setStorageUser(uid: string | null) {
  const next = uid && uid.trim() && uid !== "guest" ? uid.trim() : null;
  if (storageUser !== next) {
    storageUser = next;
    notifyStorageChange();
  }
}

export function setStorageScope(userId: string | null | undefined): void {
  setStorageUser(userId ?? null);
}

export function getStorageScope(): string {
  return storageUser || "guest";
}

function scopedKey(key: string, user = storageUser) {
  const normalizedKey = key.startsWith("neuroflow_") ? key : `neuroflow_${key}`;
  const targetUser = user && user !== "guest" ? user : null;
  return targetUser
    ? `${normalizedKey}:user:${encodeURIComponent(targetUser)}`
    : normalizedKey;
}

export function getScopedKey(baseKey: string, scope?: string): string {
  const targetScope =
    scope !== undefined
      ? scope && scope !== "guest"
        ? scope
        : null
      : storageUser;
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
export type SyncCollection = "tasks" | "notes";
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
    ) || "{}",
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
  displayName: "Bryan",
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
  | { type: "task_saved"; task: Task }
  | { type: "task_deleted"; taskId: string }
  | { type: "note_saved"; note: Note }
  | { type: "note_deleted"; noteId: string };

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
      console.warn("Storage mutation listener error:", e);
    }
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function getFromStorage<T>(key: string, defaultValue: T, scope?: string): T {
  const user =
    scope !== undefined
      ? scope && scope !== "guest"
        ? scope
        : null
      : storageUser;
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
  const user =
    scope !== undefined
      ? scope && scope !== "guest"
        ? scope
        : null
      : storageUser;
  const k = scopedKey(key, user);
  try {
    localStorage.setItem(k, JSON.stringify(value));
    notifyStorageChange();
  } catch {
    throw new Error(
      "Could not save on this device. Free storage space before continuing.",
    );
  }
}

export function formatDateKey(date: Date): string {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
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
  const key = collection === "tasks" ? STORAGE_KEYS.TASKS : STORAGE_KEYS.NOTES;
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
  type: "task" | "note" | "delete_task" | "delete_note";
  entityId: string;
  data?: any;
  timestamp: number;
}

export const offlineQueueStorage = {
  getQueue: (scope?: string): QueuedSyncOperation[] => {
    const user =
      scope !== undefined
        ? scope && scope !== "guest"
          ? scope
          : null
        : storageUser;
    if (!user) return [];
    const taskOutbox = readOutbox(user, "tasks");
    const noteOutbox = readOutbox(user, "notes");
    const items: QueuedSyncOperation[] = [];
    for (const [id, w] of Object.entries(taskOutbox)) {
      items.push({
        id,
        type: w.value ? "task" : "delete_task",
        entityId: id,
        data: w.value,
        timestamp: Date.now(),
      });
    }
    for (const [id, w] of Object.entries(noteOutbox)) {
      items.push({
        id,
        type: w.value ? "note" : "delete_note",
        entityId: id,
        data: w.value,
        timestamp: Date.now(),
      });
    }
    return items;
  },

  enqueue: (
    op: {
      type: "task" | "delete_task" | "note" | "delete_note";
      entityId: string;
      data?: any;
    },
    scope?: string,
  ): void => {
    const user =
      scope !== undefined
        ? scope && scope !== "guest"
          ? scope
          : null
        : storageUser;
    if (!user) return;
    if (op.type === "task") {
      queueWrite("tasks", op.entityId, op.data, user);
    } else if (op.type === "delete_task") {
      queueWrite("tasks", op.entityId, null, user);
    } else if (op.type === "note") {
      queueWrite("notes", op.entityId, op.data, user);
    } else if (op.type === "delete_note") {
      queueWrite("notes", op.entityId, null, user);
    }
  },

  dequeue: (opId: string, scope?: string): void => {
    const user =
      scope !== undefined
        ? scope && scope !== "guest"
          ? scope
          : null
        : storageUser;
    if (!user) return;
    const taskOutbox = readOutbox(user, "tasks");
    if (taskOutbox[opId]) {
      acknowledgeWrite(user, "tasks", opId, taskOutbox[opId].revision);
    }
    const noteOutbox = readOutbox(user, "notes");
    if (noteOutbox[opId]) {
      acknowledgeWrite(user, "notes", opId, noteOutbox[opId].revision);
    }
  },

  clearQueue: (_scope?: string): void => {},
};

// ---------------------------------------------------------------------------
// Storage Repositories & State Machine
// ---------------------------------------------------------------------------
export const LOCKED_TASK_STATUSES: readonly LockedTaskStatus[] = [
  "captured",
  "clarified",
  "picked",
  "active",
  "paused",
  "resumed",
  "finished",
] as const;

export function isLockedTaskStatus(val: unknown): val is LockedTaskStatus {
  return (
    typeof val === "string" &&
    (LOCKED_TASK_STATUSES as readonly string[]).includes(val)
  );
}

/**
 * Normalizes any incoming task record (legacy, pre-Slice-1, or raw external data)
 * into the canonical 7-state architecture while preserving all existing domain fields.
 * Migration is strictly idempotent: migrateTask(migrateTask(task)) === migrateTask(task).
 */
export function migrateTask(raw: any): Task {
  if (!raw || typeof raw !== "object") {
    return {
      id: crypto.randomUUID(),
      title: "",
      originalWording: "",
      status: "captured",
      createdAt: new Date().toISOString(),
      accumulatedActiveSeconds: 0,
      activeSegmentStartedAt: null,
      targetEndTime: null,
      microSteps: [],
      isQuickWin: false,
    };
  }

  let status: LockedTaskStatus;
  if (isLockedTaskStatus(raw.status)) {
    status = raw.status;
  } else if (raw.status === "inProgress") {
    status = "active";
  } else if (raw.status === "completed") {
    status = "finished";
  } else if (
    raw.status === "pending" ||
    raw.status === "skipped" ||
    raw.status === "blocked" ||
    !raw.status
  ) {
    status =
      (raw.microSteps && raw.microSteps.length > 0) ||
      raw.estimatedMinutes ||
      raw.dueDate
        ? "clarified"
        : "captured";
  } else {
    // Unknown or unrecognized status string: normalize safely without data loss
    status =
      (raw.microSteps && raw.microSteps.length > 0) ||
      raw.estimatedMinutes ||
      raw.dueDate
        ? "clarified"
        : "captured";
  }

  const activeSegmentStartedAt =
    raw.activeSegmentStartedAt !== undefined
      ? raw.activeSegmentStartedAt
      : (status === "active" || status === "resumed") && raw.activeStartedAt
        ? raw.activeStartedAt
        : null;

  const accumulatedActiveSeconds =
    typeof raw.accumulatedActiveSeconds === "number" &&
    !isNaN(raw.accumulatedActiveSeconds)
      ? Math.max(0, raw.accumulatedActiveSeconds)
      : 0;

  return {
    ...raw,
    id: typeof raw.id === "string" && raw.id ? raw.id : crypto.randomUUID(),
    title: raw.title || raw.originalWording || "",
    originalWording: raw.originalWording || raw.title || "",
    status,
    createdAt: raw.createdAt || new Date().toISOString(),
    accumulatedActiveSeconds,
    activeSegmentStartedAt,
    targetEndTime: raw.targetEndTime ?? null,
    microSteps: Array.isArray(raw.microSteps) ? raw.microSteps : [],
    isQuickWin: Boolean(raw.isQuickWin),
  };
}

export function getElapsedActiveSeconds(
  task: Task,
  now: number = Date.now(),
): number {
  const accumulated = task.accumulatedActiveSeconds || 0;
  if (
    (task.status === "active" || task.status === "resumed") &&
    task.activeSegmentStartedAt
  ) {
    const startMs = new Date(task.activeSegmentStartedAt).getTime();
    if (!isNaN(startMs)) {
      return accumulated + Math.max(0, Math.floor((now - startMs) / 1000));
    }
  }
  return accumulated;
}

export const taskStorage = {
  getAll: (scope?: string): Task[] => {
    const raw = getFromStorage<any[]>(STORAGE_KEYS.TASKS, [], scope);
    return Array.isArray(raw) ? raw.map(migrateTask) : [];
  },

  getAllForScope: (scope: string): Task[] => {
    const raw = getFromStorage<any[]>(STORAGE_KEYS.TASKS, [], scope);
    return Array.isArray(raw) ? raw.map(migrateTask) : [];
  },

  save: (task: Task, isRemote: boolean = false, scope?: string): void => {
    // Canonical migration ensures non-canonical or legacy statuses are never saved back to disk
    const canonical = migrateTask(task);
    const tasks = taskStorage.getAll(scope);
    const idx = tasks.findIndex((t) => t.id === canonical.id);
    if (idx >= 0) {
      tasks[idx] = canonical;
    } else {
      tasks.unshift(canonical);
    }
    setToStorage(STORAGE_KEYS.TASKS, tasks, scope);
    if (!isRemote) {
      const targetUser =
        scope !== undefined
          ? scope && scope !== "guest"
            ? scope
            : null
          : storageUser;
      if (targetUser) {
        queueWrite("tasks", canonical.id, canonical, targetUser);
      }
      notifyMutation({ type: "task_saved", task: canonical });
    }
  },

  delete: (id: string, isRemote: boolean = false, scope?: string): void => {
    const tasks = taskStorage.getAll(scope).filter((t) => t.id !== id);
    setToStorage(STORAGE_KEYS.TASKS, tasks, scope);
    AlertService.cancel(id);
    if (!isRemote) {
      const targetUser =
        scope !== undefined
          ? scope && scope !== "guest"
            ? scope
            : null
          : storageUser;
      if (targetUser) {
        queueWrite("tasks", id, null, targetUser);
      }
      notifyMutation({ type: "task_deleted", taskId: id });
    }
  },

  // 1. Capture: Saves straight to inbox with verbatim original wording, zero required forms
  captureItem: (text: string, scope?: string): Task => {
    const clean = text.trim();
    const newTask: Task = {
      id: crypto.randomUUID(),
      title: clean,
      originalWording: text,
      status: "captured",
      createdAt: new Date().toISOString(),
      accumulatedActiveSeconds: 0,
      activeSegmentStartedAt: null,
      targetEndTime: null,
      microSteps: [],
      isQuickWin: false,
    };
    taskStorage.save(newTask, false, scope);
    return newTask;
  },

  // 2. Clarify: Enhances captured item with micro-steps, duration, or notes without disturbing active/resumed/paused state
  clarifyTask: (
    id: string,
    updates: Partial<Task>,
    scope?: string,
  ): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const target = tasks.find((t) => t.id === id);
    if (!target) return null;
    if (target.status === "finished") return null; // Reject modifying finished task

    // Retain status if already active, resumed, paused, or picked; otherwise transition captured -> clarified
    const preservedStatus =
      target.status === "active" ||
      target.status === "resumed" ||
      target.status === "paused" ||
      target.status === "picked"
        ? target.status
        : "clarified";

    const updated: Task = {
      ...target,
      ...updates,
      status: preservedStatus,
    };
    taskStorage.save(updated, false, scope);
    return updated;
  },

  // 3. Pick: Designates the single next thing on the Now card.
  // Closes any running timer segment first, cancels alert, and demotes any previous picked task.
  pickTask: (id: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const target = tasks.find((t) => t.id === id);
    if (!target) return null;
    if (target.status === "finished") return null; // Reject picking finished task
    if (target.status === "picked") return target; // Idempotent

    // If currently running, close the active timer segment cleanly first
    let accumulated = target.accumulatedActiveSeconds || 0;
    if (
      (target.status === "active" || target.status === "resumed") &&
      target.activeSegmentStartedAt
    ) {
      const startMs = new Date(target.activeSegmentStartedAt).getTime();
      if (!isNaN(startMs)) {
        accumulated += Math.max(0, Math.floor((Date.now() - startMs) / 1000));
      }
      AlertService.cancel(target.id);
    }

    // Demote any other picked task back to clarified (or captured)
    tasks.forEach((t) => {
      if (t.id !== id && t.status === "picked") {
        const nextStatus: LockedTaskStatus =
          t.microSteps?.length || t.estimatedMinutes || t.dueDate
            ? "clarified"
            : "captured";
        const demoted: Task = { ...t, status: nextStatus };
        taskStorage.save(demoted, false, scope);
      }
    });

    const updated: Task = {
      ...target,
      status: "picked",
      accumulatedActiveSeconds: accumulated,
      activeSegmentStartedAt: null,
      targetEndTime: null,
    };
    taskStorage.save(updated, false, scope);
    return updated;
  },

  // 4. Start: Transitions to Active. Idempotent if already active/resumed; delegates to resumeTask if paused.
  startTask: (id: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const target = tasks.find((t) => t.id === id);
    if (!target) return null;
    if (target.status === "finished") return null; // Reject starting finished task

    // Idempotent: already running
    if (target.status === "active" || target.status === "resumed") {
      return target;
    }

    // If paused, delegate to resumeTask to maintain exact pause/resume semantics
    if (target.status === "paused") {
      return taskStorage.resumeTask(id, scope);
    }

    // Rule: Only one task can be Active at a time. Auto-pause others.
    tasks.forEach((t) => {
      if (t.id !== id && (t.status === "active" || t.status === "resumed")) {
        taskStorage.pauseTask(
          t.id,
          { lastCompletedStep: "Auto-paused to start another task" },
          scope,
        );
      }
    });

    const now = new Date();
    let targetEndTime = target.targetEndTime || null;
    if (!targetEndTime && target.estimatedMinutes) {
      const remainingSecs = Math.max(
        0,
        target.estimatedMinutes * 60 - (target.accumulatedActiveSeconds || 0),
      );
      if (remainingSecs > 0) {
        targetEndTime = new Date(
          now.getTime() + remainingSecs * 1000,
        ).toISOString();
      }
    } else if (!targetEndTime && target.dueDate) {
      targetEndTime = target.dueDate;
    }

    const updated: Task = {
      ...target,
      status: "active",
      activeSegmentStartedAt: now.toISOString(),
      targetEndTime,
    };
    taskStorage.save(updated, false, scope);

    // AlertService abstracted schedule trigger
    if (targetEndTime) {
      AlertService.schedule(updated.id, targetEndTime, updated.title);
    }

    return updated;
  },

  // 5. Pause: Preserves elapsed time and progress, cancels pending alert. Idempotent if already paused.
  pauseTask: (
    id: string,
    reentryOrNextAction?: Partial<ReentryNote> | string,
    scope?: string,
  ): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const target = tasks.find((t) => t.id === id);
    if (!target) return null;
    const extraNote: Partial<ReentryNote> =
      typeof reentryOrNextAction === "string"
        ? { nextAction: reentryOrNextAction }
        : reentryOrNextAction || {};

    // Idempotent: if already paused, update reentry note if provided without touching timer
    if (target.status === "paused") {
      if (Object.keys(extraNote).length > 0) {
        const updatedReentry: ReentryNote = {
          lastCompletedStep:
            target.reentryNote?.lastCompletedStep ||
            "Paused for context switch",
          nextAction: "Open task and take next step",
          ...target.reentryNote,
          ...extraNote,
          updatedAt: new Date().toISOString(),
        };
        const updated: Task = { ...target, reentryNote: updatedReentry };
        taskStorage.save(updated, false, scope);
        return updated;
      }
      return target;
    }

    // Guard: reject non-running states (finished, captured, clarified, picked)
    if (target.status !== "active" && target.status !== "resumed") {
      return null;
    }

    let segmentElapsed = 0;
    if (target.activeSegmentStartedAt) {
      const startMs = new Date(target.activeSegmentStartedAt).getTime();
      if (!isNaN(startMs)) {
        segmentElapsed = Math.max(0, Math.floor((Date.now() - startMs) / 1000));
      }
    }

    const updatedAccumulated =
      (target.accumulatedActiveSeconds || 0) + segmentElapsed;
    AlertService.cancel(target.id);

    const updatedReentry: ReentryNote = {
      lastCompletedStep:
        target.reentryNote?.lastCompletedStep || "Paused for context switch",
      nextAction: "Open task and take next step",
      ...target.reentryNote,
      ...extraNote,
      updatedAt: new Date().toISOString(),
    };

    const updated: Task = {
      ...target,
      status: "paused",
      accumulatedActiveSeconds: updatedAccumulated,
      activeSegmentStartedAt: null,
      targetEndTime: null,
      reentryNote: updatedReentry,
    };
    taskStorage.save(updated, false, scope);
    return updated;
  },

  // 6. Resume: Continues elapsed timer from paused total, re-schedules alert. Idempotent if already active/resumed.
  resumeTask: (id: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const target = tasks.find((t) => t.id === id);
    if (!target) return null;
    if (target.status === "finished") return null; // Reject resuming finished task

    // Idempotent: already running
    if (target.status === "resumed" || target.status === "active") {
      return target;
    }

    // Only paused tasks can be resumed.
    if (target.status !== "paused") {
      return null;
    }

    // Only one task active at a time
    tasks.forEach((t) => {
      if (t.id !== id && (t.status === "active" || t.status === "resumed")) {
        taskStorage.pauseTask(
          t.id,
          { lastCompletedStep: "Auto-paused to resume another task" },
          scope,
        );
      }
    });

    const now = new Date();
    let targetEndTime: string | null = null;
    if (target.estimatedMinutes) {
      const remainingSecs = Math.max(
        0,
        target.estimatedMinutes * 60 - (target.accumulatedActiveSeconds || 0),
      );
      if (remainingSecs > 0) {
        targetEndTime = new Date(
          now.getTime() + remainingSecs * 1000,
        ).toISOString();
      }
    } else if (target.dueDate) {
      targetEndTime = target.dueDate;
    }

    const updated: Task = {
      ...target,
      status: "resumed",
      activeSegmentStartedAt: now.toISOString(),
      targetEndTime,
    };
    taskStorage.save(updated, false, scope);

    if (targetEndTime) {
      AlertService.schedule(updated.id, targetEndTime, updated.title);
    }

    return updated;
  },

  // 7. Finish: Completes task, finalizes elapsed time, cancels alert, records completedAt. Idempotent if already finished.
  finishTask: (id: string, scope?: string): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const target = tasks.find((t) => t.id === id);
    if (!target) return null;

    // Idempotent: already finished
    if (target.status === "finished") {
      return target;
    }

    let segmentElapsed = 0;
    if (
      (target.status === "active" || target.status === "resumed") &&
      target.activeSegmentStartedAt
    ) {
      const startMs = new Date(target.activeSegmentStartedAt).getTime();
      if (!isNaN(startMs)) {
        segmentElapsed = Math.max(0, Math.floor((Date.now() - startMs) / 1000));
      }
    }

    const updatedAccumulated =
      (target.accumulatedActiveSeconds || 0) + segmentElapsed;
    AlertService.cancel(target.id);

    const updated: Task = {
      ...target,
      status: "finished",
      accumulatedActiveSeconds: updatedAccumulated,
      activeSegmentStartedAt: null,
      targetEndTime: null,
      completedAt: new Date().toISOString(),
    };
    taskStorage.save(updated, false, scope);
    return updated;
  },

  complete: (id: string, scope?: string): Task | null => {
    return taskStorage.finishTask(id, scope);
  },

  toggleStatus: (id: string, scope?: string): Task | null => {
    // Deprecated legacy toggle. Finished tasks are strictly terminal in Slice 1.
    return taskStorage.finishTask(id, scope);
  },

  updateMicroSteps: (
    id: string,
    microSteps: MicroStepItem[],
    scope?: string,
  ): Task | null => {
    const tasks = taskStorage.getAll(scope);
    const target = tasks.find((t) => t.id === id);
    if (!target) return null;
    const updated: Task = {
      ...target,
      microSteps,
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

  isCheckedToday: (
    habitId: string,
    dateStr?: string,
    scope?: string,
  ): boolean => {
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
          id: "seed-mood-yesterday",
          level: "good",
          note: "Focused on deep work after taking morning walk",
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
          id: "note-1",
          body: "Idea for evening shutdown: set timer for 8:45 PM to put phone in kitchen station.\nReduces blue light before sleep.",
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
      const targetUser =
        scope !== undefined
          ? scope && scope !== "guest"
            ? scope
            : null
          : storageUser;
      if (targetUser) {
        queueWrite("notes", note.id, note, targetUser);
      }
      notifyMutation({ type: "note_saved", note });
    }
  },

  delete: (id: string, isRemote: boolean = false, scope?: string): void => {
    const notes = noteStorage.getAll(scope).filter((n) => n.id !== id);
    setToStorage(STORAGE_KEYS.NOTES, notes, scope);
    if (!isRemote) {
      const targetUser =
        scope !== undefined
          ? scope && scope !== "guest"
            ? scope
            : null
          : storageUser;
      if (targetUser) {
        queueWrite("notes", id, null, targetUser);
      }
      notifyMutation({ type: "note_deleted", noteId: id });
    }
  },

  togglePin: (id: string, scope?: string): void => {
    const notes = noteStorage.getAll(scope);
    const n = notes.find((item) => item.id === id);
    if (!n) return;
    n.pinned = !n.pinned;
    setToStorage(STORAGE_KEYS.NOTES, notes, scope);
    const targetUser =
      scope !== undefined
        ? scope && scope !== "guest"
          ? scope
          : null
        : storageUser;
    if (targetUser) {
      queueWrite("notes", n.id, n, targetUser);
    }
    notifyMutation({ type: "note_saved", note: n });
  },
};

export const settingsStorage = {
  get: (scope?: string): AppSettings =>
    getFromStorage<AppSettings>(STORAGE_KEYS.SETTINGS, DEFAULT_SETTINGS, scope),

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
    return localStorage.getItem(scopedKey(STORAGE_KEYS.HEVY_KEY, scope)) || "";
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
    const tasks = taskStorage.getAllForScope("guest");
    const routines = routineStorage.getAllForScope("guest");
    const habits = habitStorage.getAllForScope("guest");
    const notes = noteStorage.getAllForScope("guest");

    const taskCount = tasks.length;
    const routineCount = routines.length;
    const habitCount = habits.length;
    const noteCount = notes.length;

    return {
      taskCount,
      routineCount,
      habitCount,
      noteCount,
      hasData:
        taskCount > 0 || routineCount > 0 || habitCount > 0 || noteCount > 0,
    };
  } catch {
    return {
      taskCount: 0,
      routineCount: 0,
      habitCount: 0,
      noteCount: 0,
      hasData: false,
    };
  }
}

export function isGuestImportResolved(userId: string): boolean {
  if (!userId) return true;
  return (
    localStorage.getItem(`neuroflow_${userId}_guest_import_resolved`) === "true"
  );
}

export function setGuestImportResolved(
  userId: string,
  resolved: boolean,
): void {
  if (!userId) return;
  if (resolved) {
    localStorage.setItem(`neuroflow_${userId}_guest_import_resolved`, "true");
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
  if (!targetUserId || targetUserId === "guest") {
    return {
      importedTasks: 0,
      importedRoutines: 0,
      importedHabits: 0,
      importedNotes: 0,
    };
  }

  // 1. Snapshot backup of current guest data
  const guestBackupKey = `neuroflow_guest_backup_after_import_${Date.now()}`;
  const guestSnapshot = {
    exportedAt: new Date().toISOString(),
    tasks: taskStorage.getAllForScope("guest"),
    routines: routineStorage.getAllForScope("guest"),
    habits: habitStorage.getAllForScope("guest"),
    habitCheckIns: habitStorage.getCheckIns(undefined, "guest"),
    moods: moodStorage.getAll("guest"),
    notes: noteStorage.getAllForScope("guest"),
  };
  localStorage.setItem(guestBackupKey, JSON.stringify(guestSnapshot));

  // 2. Non-destructive merge of tasks
  const guestTasks = taskStorage.getAllForScope("guest");
  const accountTasks = taskStorage.getAll(targetUserId);
  const existingTaskIds = new Set(accountTasks.map((t) => t.id));
  let importedTasks = 0;

  for (const t of guestTasks) {
    if (!existingTaskIds.has(t.id)) {
      accountTasks.unshift(t);
      importedTasks++;
      queueWrite("tasks", t.id, t, targetUserId);
      notifyMutation({ type: "task_saved", task: t });
    }
  }
  setToStorage(STORAGE_KEYS.TASKS, accountTasks, targetUserId);

  // 3. Non-destructive merge of routines
  const guestRoutines = routineStorage.getAllForScope("guest");
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
  const guestHabits = habitStorage.getAllForScope("guest");
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
  const guestNotes = noteStorage.getAllForScope("guest");
  const accountNotes = noteStorage.getAll(targetUserId);
  const existingNoteIds = new Set(accountNotes.map((n) => n.id));
  let importedNotes = 0;

  for (const n of guestNotes) {
    if (!existingNoteIds.has(n.id)) {
      accountNotes.unshift(n);
      importedNotes++;
      queueWrite("notes", n.id, n, targetUserId);
      notifyMutation({ type: "note_saved", note: n });
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
  const exportedHabits = includeSensitive
    ? allHabits
    : filterNonSensitiveHabits(allHabits);

  return {
    version: 2,
    scope: getStorageScope(),
    privacyTier: includeSensitive
      ? "full-including-sensitive"
      : "standard-non-sensitive",
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
