import { beforeEach, test } from "node:test";
import assert from "node:assert/strict";
import {
  migrateTask,
  taskStorage,
  setStorageUser,
  getElapsedActiveSeconds,
  LOCKED_TASK_STATUSES,
  isLockedTaskStatus,
} from "../src/lib/storage";
import { AlertService } from "../src/lib/alerts";
import { SEED_TASKS } from "../src/lib/constants";
import type { Task } from "../src/types";

const values = new Map<string, string>();
Object.defineProperty(globalThis, "localStorage", {
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

test("migration: legacy task records (pending, inProgress, completed, skipped, blocked) map cleanly to 7 states", () => {
  // Legacy pending with no details -> captured
  const legacyPending = migrateTask({
    id: "leg-1",
    title: "Buy milk",
    status: "pending",
    createdAt: "2026-10-01T10:00:00Z",
  });
  assert.equal(legacyPending.status, "captured");
  assert.equal(legacyPending.originalWording, "Buy milk");
  assert.equal(legacyPending.accumulatedActiveSeconds, 0);

  // Legacy pending with micro-steps or duration -> clarified
  const legacyClarified = migrateTask({
    id: "leg-2",
    title: "Clean garage",
    status: "pending",
    estimatedMinutes: 30,
    microSteps: [{ id: "s1", title: "Sweep floor", completed: false }],
  });
  assert.equal(legacyClarified.status, "clarified");

  // Legacy inProgress -> active with activeSegmentStartedAt populated
  const legacyInProgress = migrateTask({
    id: "leg-3",
    title: "Draft email",
    status: "inProgress",
    activeStartedAt: "2026-10-01T12:00:00Z",
  });
  assert.equal(legacyInProgress.status, "active");
  assert.equal(legacyInProgress.activeSegmentStartedAt, "2026-10-01T12:00:00Z");

  // Legacy completed -> finished
  const legacyCompleted = migrateTask({
    id: "leg-4",
    title: "Pay utility bill",
    status: "completed",
    completedAt: "2026-10-01T14:00:00Z",
  });
  assert.equal(legacyCompleted.status, "finished");

  // Legacy skipped or blocked -> captured
  const legacySkipped = migrateTask({
    id: "leg-5",
    title: "Read book",
    status: "skipped",
  });
  assert.equal(legacySkipped.status, "captured");
});

test("migration: SEED_TASKS and complex pre-Slice-1 records retain all fields and normalize unknown statuses", () => {
  // 1. Verify SEED_TASKS migration preserves energy, notes, dueDate, isQuickWin, etc.
  for (const seed of SEED_TASKS) {
    const migrated = migrateTask(seed);
    assert.ok(isLockedTaskStatus(migrated.status));
    assert.equal(migrated.id, seed.id);
    assert.equal(migrated.title, seed.title);
    assert.equal(migrated.notes, seed.notes);
    assert.equal(migrated.energy, seed.energy);
    assert.equal(migrated.isQuickWin, seed.isQuickWin);
    assert.equal(migrated.dueDate, seed.dueDate);
    assert.equal(migrated.estimatedMinutes, seed.estimatedMinutes);
    // Since seed tasks have estimatedMinutes or dueDate, they map to 'clarified'
    assert.equal(migrated.status, "clarified");
  }

  // 2. Complex record with Google Task ID, notes, and unknown status 'archived'
  const complexRecord = {
    id: "complex-99",
    title: "Sync quarterly tax returns",
    originalWording: "Tax returns Q3",
    notes: "Include 1099-NEC and receipt ledger",
    energy: "high" as const,
    status: "archived", // Unknown legacy status
    createdAt: "2026-08-15T09:00:00Z",
    dueDate: "2026-09-15T17:00:00Z",
    googleTaskId: "gtask-xyz-889",
    isQuickWin: false,
    estimatedMinutes: 60,
    microSteps: [
      { id: "ms-1", title: "Export Stripe transactions", completed: true },
      { id: "ms-2", title: "Upload to CPA portal", completed: false },
    ],
  };

  const migratedComplex = migrateTask(complexRecord);
  assert.equal(migratedComplex.status, "clarified"); // Has microSteps and duration
  assert.equal(migratedComplex.googleTaskId, "gtask-xyz-889");
  assert.equal(migratedComplex.notes, "Include 1099-NEC and receipt ledger");
  assert.equal(migratedComplex.energy, "high");
  assert.equal(migratedComplex.microSteps?.length, 2);
  assert.equal(migratedComplex.isQuickWin, false);

  // 3. Repeated migration is strictly idempotent
  const twiceMigrated = migrateTask(migratedComplex);
  assert.deepEqual(twiceMigrated, migratedComplex);

  // 4. taskStorage.save prevents saving legacy or non-canonical statuses back to disk
  taskStorage.save({
    ...complexRecord,
    status: "pending" as any,
  });

  const rawSavedJson = values.get("neuroflow_tasks");
  assert.ok(rawSavedJson);
  const parsed = JSON.parse(rawSavedJson);
  const persisted = parsed.find((t: any) => t.id === "complex-99");
  assert.ok(persisted);
  assert.equal(persisted.status, "clarified"); // Normalized before saving
  assert.equal(persisted.googleTaskId, "gtask-xyz-889");
});

test("7-state transitions: Capture → Clarify → Pick → Start → Pause → Resume → Finish", () => {
  // 1. Capture: raw verbatim capture, zero required fields
  const captured = taskStorage.captureItem("Fix leaking bathroom tap tonight");
  assert.equal(captured.status, "captured");
  assert.equal(captured.originalWording, "Fix leaking bathroom tap tonight");
  assert.equal(captured.title, "Fix leaking bathroom tap tonight");
  assert.equal(captured.accumulatedActiveSeconds, 0);

  // 2. Clarify: breakdown micro-steps and duration
  const clarified = taskStorage.clarifyTask(captured.id, {
    estimatedMinutes: 20,
    microSteps: [
      { id: "m1", title: "Turn off water valve under sink", completed: false },
      {
        id: "m2",
        title: "Unscrew aerator and replace rubber washer",
        completed: false,
      },
    ],
  });
  assert.ok(clarified);
  assert.equal(clarified.status, "clarified");
  assert.equal(clarified.estimatedMinutes, 20);
  assert.equal(clarified.microSteps?.length, 2);

  // 3. Pick: designate as the single next thing
  const picked = taskStorage.pickTask(captured.id);
  assert.ok(picked);
  assert.equal(picked.status, "picked");

  // 4. Start: transitions to Active, records start timestamp, schedules alert
  const active = taskStorage.startTask(captured.id);
  assert.ok(active);
  assert.equal(active.status, "active");
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
    lastCompletedStep: "Turned off water valve",
    nextAction: "Unscrew aerator",
  });
  assert.ok(paused);
  assert.equal(paused.status, "paused");
  assert.equal(paused.activeSegmentStartedAt, null);
  assert.equal(paused.targetEndTime, null);
  assert.ok((paused.accumulatedActiveSeconds || 0) >= 10);
  assert.equal(paused.reentryNote?.lastCompletedStep, "Turned off water valve");
  assert.equal(paused.reentryNote?.nextAction, "Unscrew aerator");
  // Alert cancelled on pause
  assert.equal(AlertService.getPending(captured.id), undefined);

  // 6. Resume: restarts timer from accumulated total, re-schedules alert
  const resumed = taskStorage.resumeTask(captured.id);
  assert.ok(resumed);
  assert.equal(resumed.status, "resumed");
  assert.ok(resumed.activeSegmentStartedAt);
  assert.ok(AlertService.getPending(captured.id));

  // 7. Finish: marks finished, records completedAt, finalizes elapsed time, cancels alert
  // Simulate resumed running for another 5 seconds
  const resumedStart = new Date(Date.now() - 5000).toISOString();
  taskStorage.save({ ...resumed, activeSegmentStartedAt: resumedStart });

  const finished = taskStorage.finishTask(captured.id);
  assert.ok(finished);
  assert.equal(finished.status, "finished");
  assert.ok((finished.accumulatedActiveSeconds || 0) >= 15);
  assert.ok(finished.completedAt);
  assert.equal(finished.activeSegmentStartedAt, null);
  assert.equal(finished.targetEndTime, null);
  // Alert cancelled on finish
  assert.equal(AlertService.getPending(captured.id), undefined);
});

test("lifecycle guards & idempotency: repeated actions cannot corrupt timestamps or accumulate duplicate time", () => {
  const task = taskStorage.captureItem("Idempotency Guard Test");
  taskStorage.clarifyTask(task.id, { estimatedMinutes: 15 });

  // 1. Initial start
  const started1 = taskStorage.startTask(task.id)!;
  assert.equal(started1.status, "active");
  const segment1StartedAt = started1.activeSegmentStartedAt;
  assert.ok(segment1StartedAt);

  // Duplicate Start: must be idempotent and NEVER overwrite activeSegmentStartedAt
  const duplicateStart = taskStorage.startTask(task.id)!;
  assert.equal(duplicateStart.status, "active");
  assert.equal(duplicateStart.activeSegmentStartedAt, segment1StartedAt);

  // Simulate 20 seconds elapsed
  const running20s = new Date(Date.now() - 20000).toISOString();
  taskStorage.save({ ...started1, activeSegmentStartedAt: running20s });

  // 2. Pause
  const paused1 = taskStorage.pauseTask(task.id, "Next: Review diffs")!;
  assert.equal(paused1.status, "paused");
  const accumulatedAfterPause1 = paused1.accumulatedActiveSeconds!;
  assert.ok(accumulatedAfterPause1 >= 20);

  // Duplicate Pause: must be idempotent and NOT accumulate extra time
  const duplicatePause = taskStorage.pauseTask(
    task.id,
    "Next: Review diffs updated",
  )!;
  assert.equal(duplicatePause.status, "paused");
  assert.equal(duplicatePause.accumulatedActiveSeconds, accumulatedAfterPause1);
  assert.equal(
    duplicatePause.reentryNote?.nextAction,
    "Next: Review diffs updated",
  );

  // 3. Resume
  const resumed1 = taskStorage.resumeTask(task.id)!;
  assert.equal(resumed1.status, "resumed");
  const resumedSegmentStartedAt = resumed1.activeSegmentStartedAt;
  assert.ok(resumedSegmentStartedAt);

  // Duplicate Resume: must be idempotent and NOT overwrite activeSegmentStartedAt
  const duplicateResume = taskStorage.resumeTask(task.id)!;
  assert.equal(duplicateResume.status, "resumed");
  assert.equal(duplicateResume.activeSegmentStartedAt, resumedSegmentStartedAt);

  // 4. Pick running task: must close running timer segment cleanly before setting picked
  const runningBeforePick = new Date(Date.now() - 15000).toISOString();
  taskStorage.save({ ...resumed1, activeSegmentStartedAt: runningBeforePick });

  const pickedFromRunning = taskStorage.pickTask(task.id)!;
  assert.equal(pickedFromRunning.status, "picked");
  assert.equal(pickedFromRunning.activeSegmentStartedAt, null);
  assert.ok(
    pickedFromRunning.accumulatedActiveSeconds! >= accumulatedAfterPause1 + 15,
  );
  // Alert cancelled on pick
  assert.equal(AlertService.getPending(task.id), undefined);

  // Duplicate Pick: idempotent
  const duplicatePick = taskStorage.pickTask(task.id)!;
  assert.equal(duplicatePick.status, "picked");

  // 5. Finish
  const finished = taskStorage.finishTask(task.id)!;
  assert.equal(finished.status, "finished");
  const finalAccumulated = finished.accumulatedActiveSeconds!;
  const completedAt = finished.completedAt!;
  assert.ok(completedAt);

  // Duplicate Finish: idempotent
  const duplicateFinish = taskStorage.finishTask(task.id)!;
  assert.equal(duplicateFinish.status, "finished");
  assert.equal(duplicateFinish.accumulatedActiveSeconds, finalAccumulated);
  assert.equal(duplicateFinish.completedAt, completedAt);

  // 6. Invalid transitions on finished task must be rejected
  assert.equal(taskStorage.startTask(task.id), null);
  assert.equal(taskStorage.resumeTask(task.id), null);
  assert.equal(taskStorage.pauseTask(task.id), null);
  assert.equal(taskStorage.pickTask(task.id), null);
  assert.equal(taskStorage.clarifyTask(task.id, { title: "Changed" }), null);

  // Confirm task is still finished
  const taskAfterInvalid = taskStorage.getAll().find((t) => t.id === task.id)!;
  assert.equal(taskAfterInvalid.status, "finished");
});

test("rule: only one task may be active at a time; starting a second task pauses the first", () => {
  const task1 = taskStorage.captureItem("Task 1");
  const task2 = taskStorage.captureItem("Task 2");

  taskStorage.startTask(task1.id);
  const running1 = taskStorage.getAll().find((t) => t.id === task1.id);
  assert.equal(running1?.status, "active");

  // Start second task
  taskStorage.startTask(task2.id);

  const updatedTasks = taskStorage.getAll();
  const t1 = updatedTasks.find((t) => t.id === task1.id);
  const t2 = updatedTasks.find((t) => t.id === task2.id);

  assert.equal(t1?.status, "paused");
  assert.equal(t2?.status, "active");
});

test("alert-ready timer contract: reaching deadline does not finish task; pause and finish cancel alert", () => {
  const task = taskStorage.captureItem("Deadline Task");
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
  assert.equal(reloaded?.status, "active");
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

test("pauseTask guards: calling pauseTask on unstarted or finished tasks returns null without mutating state", () => {
  // 1. Captured task cannot be paused
  const captured = taskStorage.captureItem("Unstarted Task");
  assert.equal(taskStorage.pauseTask(captured.id), null);
  assert.equal(
    taskStorage.getAll().find((t) => t.id === captured.id)?.status,
    "captured",
  );

  // 2. Clarified task cannot be paused
  const clarified = taskStorage.clarifyTask(captured.id, {
    estimatedMinutes: 20,
  })!;
  assert.equal(taskStorage.pauseTask(clarified.id), null);
  assert.equal(
    taskStorage.getAll().find((t) => t.id === captured.id)?.status,
    "clarified",
  );

  // 3. Picked task cannot be paused
  const picked = taskStorage.pickTask(captured.id)!;
  assert.equal(taskStorage.pauseTask(picked.id), null);
  assert.equal(
    taskStorage.getAll().find((t) => t.id === captured.id)?.status,
    "picked",
  );

  // 4. Starting a task auto-pauses other active tasks smoothly without breaking on guards
  const taskA = taskStorage.captureItem("Task A");
  const taskB = taskStorage.captureItem("Task B");
  taskStorage.startTask(taskA.id);
  assert.equal(
    taskStorage.getAll().find((t) => t.id === taskA.id)?.status,
    "active",
  );

  taskStorage.startTask(taskB.id);
  assert.equal(
    taskStorage.getAll().find((t) => t.id === taskA.id)?.status,
    "paused",
  );
  assert.equal(
    taskStorage.getAll().find((t) => t.id === taskB.id)?.status,
    "active",
  );

  // 5. Finished task cannot be paused
  const finished = taskStorage.finishTask(taskB.id)!;
  assert.equal(finished.status, "finished");
  assert.equal(taskStorage.pauseTask(taskB.id), null);
  assert.equal(
    taskStorage.getAll().find((t) => t.id === taskB.id)?.status,
    "finished",
  );
});

test("startTask targetEndTime edge case: re-starting a demoted task subtracts prior accumulatedActiveSeconds", () => {
  const task = taskStorage.captureItem("Demoted & Restarted Task");
  taskStorage.clarifyTask(task.id, { estimatedMinutes: 20 }); // 20 minutes = 1200 seconds
  taskStorage.pickTask(task.id);

  // Start task
  const started = taskStorage.startTask(task.id)!;
  assert.ok(started.targetEndTime);

  // Simulate task running for 5 minutes (300 seconds)
  const fiveMinutesAgo = new Date(Date.now() - 300000).toISOString();
  taskStorage.save({
    ...started,
    activeSegmentStartedAt: fiveMinutesAgo,
  });

  // Pick task again: demotes running task to picked, closing segment
  taskStorage.pickTask(task.id);
  const picked = taskStorage.getAll().find((t) => t.id === task.id)!;
  assert.equal(picked.status, "picked");
  assert.equal(picked.activeSegmentStartedAt, null);
  assert.equal(picked.targetEndTime, null);
  assert.ok((picked.accumulatedActiveSeconds || 0) >= 300);

  // Now start task again via startTask: targetEndTime must be computed from remaining ~15 minutes, NOT full 20 minutes!
  const nowMs = Date.now();
  const restarted = taskStorage.startTask(task.id)!;
  assert.equal(restarted.status, "active");
  assert.ok(restarted.targetEndTime);

  const targetMs = new Date(restarted.targetEndTime).getTime();
  const diffSecs = Math.round((targetMs - nowMs) / 1000);
  // Remaining seconds should be around 1200 - 300 = 900 seconds (allow ±5 seconds)
  assert.ok(
    diffSecs >= 895 && diffSecs <= 905,
    `Remaining seconds (${diffSecs}) should be ~900s, not 1200s`,
  );
});
