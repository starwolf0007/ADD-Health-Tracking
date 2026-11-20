import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  migrateTask,
  taskStorage,
  setStorageUser,
  getElapsedActiveSeconds,
} from '../src/lib/storage';
import { AlertService } from '../src/lib/alerts';
import type { Task } from '../src/types';

const values = new Map<string, string>();
Object.defineProperty(globalThis, 'localStorage', {
  value: {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => {
      values.set(key, value);
    },
    removeItem: (key: string) => {
      values.delete(key);
    },
  },
  configurable: true,
});

beforeEach(() => {
  values.clear();
  setStorageUser(null);
  AlertService.clearAll();
});

test('migration: legacy task records (pending, inProgress, completed, skipped, blocked) map cleanly to 7 states', () => {
  // Legacy pending with no details -> captured
  const legacyPending = migrateTask({
    id: 'leg-1',
    title: 'Buy milk',
    status: 'pending',
    createdAt: '2026-10-01T10:00:00Z',
  });
  assert.equal(legacyPending.status, 'captured');
  assert.equal(legacyPending.originalWording, 'Buy milk');
  assert.equal(legacyPending.accumulatedActiveSeconds, 0);

  // Legacy pending with micro-steps or duration -> clarified
  const legacyClarified = migrateTask({
    id: 'leg-2',
    title: 'Clean garage',
    status: 'pending',
    estimatedMinutes: 30,
    microSteps: [{ id: 's1', title: 'Sweep floor', completed: false }],
  });
  assert.equal(legacyClarified.status, 'clarified');

  // Legacy inProgress -> active with activeSegmentStartedAt populated
  const legacyInProgress = migrateTask({
    id: 'leg-3',
    title: 'Draft email',
    status: 'inProgress',
    activeStartedAt: '2026-10-01T12:00:00Z',
  });
  assert.equal(legacyInProgress.status, 'active');
  assert.equal(legacyInProgress.activeSegmentStartedAt, '2026-10-01T12:00:00Z');

  // Legacy completed -> finished
  const legacyCompleted = migrateTask({
    id: 'leg-4',
    title: 'Pay utility bill',
    status: 'completed',
    completedAt: '2026-10-01T14:00:00Z',
  });
  assert.equal(legacyCompleted.status, 'finished');

  // Legacy skipped or blocked -> captured
  const legacySkipped = migrateTask({
    id: 'leg-5',
    title: 'Read book',
    status: 'skipped',
  });
  assert.equal(legacySkipped.status, 'captured');
});

test('7-state transitions: Capture → Clarify → Pick → Start → Pause → Resume → Finish', () => {
  // 1. Capture: raw verbatim capture, zero required fields
  const captured = taskStorage.captureItem('Fix leaking bathroom tap tonight');
  assert.equal(captured.status, 'captured');
  assert.equal(captured.originalWording, 'Fix leaking bathroom tap tonight');
  assert.equal(captured.title, 'Fix leaking bathroom tap tonight');
  assert.equal(captured.accumulatedActiveSeconds, 0);

  // 2. Clarify: breakdown micro-steps and duration
  const clarified = taskStorage.clarifyTask(captured.id, {
    estimatedMinutes: 20,
    microSteps: [
      { id: 'm1', title: 'Turn off water valve under sink', completed: false },
      { id: 'm2', title: 'Unscrew aerator and replace rubber washer', completed: false },
    ],
  });
  assert.ok(clarified);
  assert.equal(clarified.status, 'clarified');
  assert.equal(clarified.estimatedMinutes, 20);
  assert.equal(clarified.microSteps?.length, 2);

  // 3. Pick: designate as the single next thing
  const picked = taskStorage.pickTask(captured.id);
  assert.ok(picked);
  assert.equal(picked.status, 'picked');

  // 4. Start: transitions to Active, records start timestamp, schedules alert
  const active = taskStorage.startTask(captured.id);
  assert.ok(active);
  assert.equal(active.status, 'active');
  assert.ok(active.activeSegmentStartedAt);
  assert.ok(active.targetEndTime);
  // AlertService abstracted contract: schedule was called
  const alert = AlertService.getPending(captured.id);
  assert.ok(alert);
  assert.equal(alert.targetEndTime, active.targetEndTime);

  // 5. Pause: saves reentry note, accumulates elapsed seconds, cancels pending alert
  // Simulate active running for 10 seconds
  const startedAt = new Date(Date.now() - 10000).toISOString();
  taskStorage.save({ ...active, activeSegmentStartedAt: startedAt });

  const paused = taskStorage.pauseTask(captured.id, {
    lastCompletedStep: 'Turned off water valve',
    nextAction: 'Unscrew aerator',
  });
  assert.ok(paused);
  assert.equal(paused.status, 'paused');
  assert.equal(paused.activeSegmentStartedAt, null);
  assert.equal(paused.targetEndTime, null);
  assert.ok((paused.accumulatedActiveSeconds || 0) >= 10);
  assert.equal(paused.reentryNote?.lastCompletedStep, 'Turned off water valve');
  assert.equal(paused.reentryNote?.nextAction, 'Unscrew aerator');
  // Alert cancelled on pause
  assert.equal(AlertService.getPending(captured.id), undefined);

  // 6. Resume: restarts timer from accumulated total, re-schedules alert
  const resumed = taskStorage.resumeTask(captured.id);
  assert.ok(resumed);
  assert.equal(resumed.status, 'resumed');
  assert.ok(resumed.activeSegmentStartedAt);
  assert.ok(AlertService.getPending(captured.id));

  // 7. Finish: marks finished, records completedAt, finalizes elapsed time, cancels alert
  // Simulate resumed running for another 5 seconds
  const resumedStart = new Date(Date.now() - 5000).toISOString();
  taskStorage.save({ ...resumed, activeSegmentStartedAt: resumedStart });

  const finished = taskStorage.finishTask(captured.id);
  assert.ok(finished);
  assert.equal(finished.status, 'finished');
  assert.ok((finished.accumulatedActiveSeconds || 0) >= 15);
  assert.ok(finished.completedAt);
  assert.equal(finished.activeSegmentStartedAt, null);
  assert.equal(finished.targetEndTime, null);
  // Alert cancelled on finish
  assert.equal(AlertService.getPending(captured.id), undefined);
});

test('rule: only one task may be active at a time; starting a second task pauses the first', () => {
  const task1 = taskStorage.captureItem('Task 1');
  const task2 = taskStorage.captureItem('Task 2');

  taskStorage.startTask(task1.id);
  const running1 = taskStorage.getAll().find((t) => t.id === task1.id);
  assert.equal(running1?.status, 'active');

  // Start second task
  taskStorage.startTask(task2.id);

  const updatedTasks = taskStorage.getAll();
  const t1 = updatedTasks.find((t) => t.id === task1.id);
  const t2 = updatedTasks.find((t) => t.id === task2.id);

  assert.equal(t1?.status, 'paused');
  assert.equal(t2?.status, 'active');
});

test('alert-ready timer contract: reaching deadline does not finish task; pause and finish cancel alert', () => {
  const task = taskStorage.captureItem('Deadline Task');
  taskStorage.clarifyTask(task.id, { estimatedMinutes: 10 });
  const started = taskStorage.startTask(task.id);
  assert.ok(started?.targetEndTime);

  // Alert is scheduled
  assert.ok(AlertService.getPending(task.id));

  // Simulate wall-clock time passing past deadline
  const pastTarget = new Date(Date.now() - 5000).toISOString();
  const pastStarted = new Date(Date.now() - 65000).toISOString();
  taskStorage.save({
    ...started,
    targetEndTime: pastTarget,
    activeSegmentStartedAt: pastStarted,
  });

  // Task is still active! Reaching deadline does NOT finish task.
  const reloaded = taskStorage.getAll().find((t) => t.id === task.id);
  assert.equal(reloaded?.status, 'active');
  const elapsed = getElapsedActiveSeconds(reloaded!);
  assert.ok(elapsed >= 65);

  // Pause cancels alert
  taskStorage.pauseTask(task.id);
  assert.equal(AlertService.getPending(task.id), undefined);

  // Resume and then finish cancels alert
  taskStorage.resumeTask(task.id);
  assert.ok(AlertService.getPending(task.id));
  taskStorage.finishTask(task.id);
  assert.equal(AlertService.getPending(task.id), undefined);
});
