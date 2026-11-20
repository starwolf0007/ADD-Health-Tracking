import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  taskStorage,
  setStorageUser,
  getElapsedActiveSeconds,
  migrateTask,
} from '../src/lib/storage';
import type { Task } from '../src/types';

// Simulated persistent localStorage across process lifecycles
const disk = new Map<string, string>();
Object.defineProperty(globalThis, 'localStorage', {
  value: {
    getItem: (key: string) => disk.get(key) ?? null,
    setItem: (key: string, value: string) => {
      disk.set(key, value);
    },
    removeItem: (key: string) => {
      disk.delete(key);
    },
  },
  configurable: true,
});

beforeEach(() => {
  disk.clear();
  setStorageUser(null);
});

test('timer restoration: killing process and reopening confirms persisted timestamps restore correct elapsed time', () => {
  // --- SESSION 1: Process is running ---
  const task = taskStorage.captureItem('Important Deep Work');
  taskStorage.clarifyTask(task.id, { estimatedMinutes: 25 });
  taskStorage.pickTask(task.id);

  // Start task 120 seconds ago
  const twoMinutesAgo = new Date(Date.now() - 120000).toISOString();
  taskStorage.startTask(task.id);
  const activeTask = taskStorage.getAll().find((t) => t.id === task.id)!;
  // Artificially simulate 120s running interval and 45s previously accumulated
  taskStorage.save({
    ...activeTask,
    accumulatedActiveSeconds: 45,
    activeSegmentStartedAt: twoMinutesAgo,
  });

  // Verify running session calculates 45 + 120 = 165s
  const session1Elapsed = getElapsedActiveSeconds(
    taskStorage.getAll().find((t) => t.id === task.id)!
  );
  assert.ok(session1Elapsed >= 165);

  // --- SIMULATED PROCESS KILL ---
  // In-memory JavaScript heap dies. No setInterval is running.
  // Disk (localStorage) only holds raw JSON strings.
  const serializedTasks = disk.get('neuroflow_tasks');
  assert.ok(serializedTasks, 'Tasks must be persisted on disk');

  // Verify timestamps stored, NOT interval tick counters
  const parsedDisk = JSON.parse(serializedTasks!);
  const persistedRecord = parsedDisk.find((t: any) => t.id === task.id);
  assert.equal(persistedRecord.status, 'active');
  assert.equal(persistedRecord.accumulatedActiveSeconds, 45);
  assert.equal(persistedRecord.activeSegmentStartedAt, twoMinutesAgo);

  // --- SESSION 2: Process boots up fresh from disk ---
  // Cold reload: re-read disk and migrate
  const coldTasks = (JSON.parse(disk.get('neuroflow_tasks')!) as any[]).map(migrateTask);
  const restoredTask = coldTasks.find((t) => t.id === task.id)!;

  assert.equal(restoredTask.status, 'active');
  assert.equal(restoredTask.accumulatedActiveSeconds, 45);
  assert.equal(restoredTask.activeSegmentStartedAt, twoMinutesAgo);

  // Restored elapsed time uses persisted timestamp diffing
  const session2Elapsed = getElapsedActiveSeconds(restoredTask);
  assert.ok(
    session2Elapsed >= 165,
    `Elapsed time must be at least 165s, got ${session2Elapsed}`
  );

  // Now pause the restored task in Session 2
  taskStorage.pauseTask(restoredTask.id, { lastCompletedStep: 'Wrote introduction' });
  const pausedTask = taskStorage.getAll().find((t) => t.id === task.id)!;
  assert.equal(pausedTask.status, 'paused');
  assert.equal(pausedTask.activeSegmentStartedAt, null);
  assert.ok(
    pausedTask.accumulatedActiveSeconds! >= 165,
    'Accumulated time after pause includes all previous active time'
  );

  // --- SIMULATED PROCESS KILL 2 ---
  // Cold reboot again while paused
  const coldPausedTasks = (JSON.parse(disk.get('neuroflow_tasks')!) as any[]).map(migrateTask);
  const restoredPaused = coldPausedTasks.find((t) => t.id === task.id)!;

  assert.equal(restoredPaused.status, 'paused');
  assert.equal(restoredPaused.activeSegmentStartedAt, null);
  assert.equal(
    restoredPaused.accumulatedActiveSeconds,
    pausedTask.accumulatedActiveSeconds
  );
  // Elapsed time for paused task does not increase while app was closed
  assert.equal(
    getElapsedActiveSeconds(restoredPaused),
    pausedTask.accumulatedActiveSeconds
  );
});
