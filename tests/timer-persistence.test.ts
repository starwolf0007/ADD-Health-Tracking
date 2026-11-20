import { test } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { execFileSync } from "node:child_process";

/**
 * Cross-Process Timer Persistence & Restoration Verification
 *
 * Requirements:
 * 1. Multi-process verification using separate Node processes sharing a real persisted disk file.
 * 2. Active timer continues from timestamp diff across separate processes (never interval ticks).
 * 3. Paused timer does not accrue time while process is stopped or dead.
 * 4. Repeated resume/start cannot reset accumulated work or corrupt timestamps.
 */

test("timer persistence: real multi-process verification across independent Node process lifecycles", () => {
  const tempDir = os.tmpdir();
  const storageFilePath = path.join(
    tempDir,
    `neuroflow_timer_storage_${Date.now()}_${Math.random().toString(36).substring(7)}.json`,
  );

  // Helper script template that equips child Node processes with disk-backed localStorage
  const childPreamble = `
    const fs = require('fs');
    const storageFile = process.env.TEST_STORAGE_FILE;

    globalThis.localStorage = {
      getItem(key) {
        if (!fs.existsSync(storageFile)) return null;
        try {
          const data = JSON.parse(fs.readFileSync(storageFile, 'utf8'));
          return data[key] ?? null;
        } catch { return null; }
      },
      setItem(key, value) {
        let data = {};
        if (fs.existsSync(storageFile)) {
          try { data = JSON.parse(fs.readFileSync(storageFile, 'utf8')); } catch {}
        }
        data[key] = String(value);
        fs.writeFileSync(storageFile, JSON.stringify(data, null, 2), 'utf8');
      },
      removeItem(key) {
        if (!fs.existsSync(storageFile)) return;
        try {
          const data = JSON.parse(fs.readFileSync(storageFile, 'utf8'));
          delete data[key];
          fs.writeFileSync(storageFile, JSON.stringify(data, null, 2), 'utf8');
        } catch {}
      }
    };
  `;

  function runChild(code: string): string {
    const fullScript = `
      ${childPreamble}
      (async () => {
        ${code}
      })().catch(err => {
        console.error(err);
        process.exit(1);
      });
    `;

    return execFileSync(
      process.execPath,
      ["--import", "tsx", "-e", fullScript],
      {
        cwd: process.cwd(),
        env: {
          ...process.env,
          TEST_STORAGE_FILE: storageFilePath,
        },
        encoding: "utf8",
      },
    ).trim();
  }

  let taskId: string;

  try {
    // -------------------------------------------------------------------------
    // PROCESS 1: Bootstraps task, starts active timer, persists to disk, and EXITS
    // -------------------------------------------------------------------------
    const proc1Output = runChild(`
      const { taskStorage } = await import('./src/lib/storage');

      const task = taskStorage.captureItem('Cross-Process Timer Test');
      taskStorage.clarifyTask(task.id, { estimatedMinutes: 30 });
      taskStorage.pickTask(task.id);

      // Start task and simulate prior 45s accumulated + active segment started 60s ago
      taskStorage.startTask(task.id);
      const running = taskStorage.getAll().find(t => t.id === task.id);

      const sixtySecondsAgo = new Date(Date.now() - 60000).toISOString();
      taskStorage.save({
        ...running,
        accumulatedActiveSeconds: 45,
        activeSegmentStartedAt: sixtySecondsAgo,
      });

      console.log(JSON.stringify({ taskId: task.id }));
    `);

    const { taskId: p1TaskId } = JSON.parse(proc1Output);
    taskId = p1TaskId;
    assert.ok(taskId, "Task ID must be created in Process 1");

    // Confirm file exists on real disk and contains pure JSON timestamps (no tick counters)
    const rawDiskContent = fs.readFileSync(storageFilePath, "utf8");
    assert.ok(rawDiskContent.includes(taskId));
    const diskParsed = JSON.parse(JSON.parse(rawDiskContent).neuroflow_tasks);
    const persistedP1 = diskParsed.find((t: any) => t.id === taskId);
    assert.equal(persistedP1.status, "active");
    assert.equal(persistedP1.accumulatedActiveSeconds, 45);
    assert.ok(persistedP1.activeSegmentStartedAt);

    // -------------------------------------------------------------------------
    // PROCESS 2: Fresh process boots from disk. Confirms active timer diffing,
    // pauses task with reentry note, persists, and EXITS
    // -------------------------------------------------------------------------
    const proc2Output = runChild(`
      const { taskStorage, getElapsedActiveSeconds } = await import('./src/lib/storage');

      const tasks = taskStorage.getAll();
      const task = tasks.find(t => t.id === '${taskId}');
      if (!task) throw new Error('Task not found on disk');

      // Active timer continues calculating from timestamp diff
      const elapsed = getElapsedActiveSeconds(task);

      // Now pause the task
      const paused = taskStorage.pauseTask(task.id, {
        lastCompletedStep: 'Finished research in Process 2',
        nextAction: 'Write code in Process 3'
      });

      console.log(JSON.stringify({
        status: paused.status,
        accumulated: paused.accumulatedActiveSeconds,
        elapsedInProc2: elapsed,
        reentry: paused.reentryNote
      }));
    `);

    const proc2Result = JSON.parse(proc2Output);
    assert.equal(proc2Result.status, "paused");
    assert.ok(
      proc2Result.elapsedInProc2 >= 105,
      `Process 2 elapsed time (${proc2Result.elapsedInProc2}s) should be at least 105s (45s + 60s)`,
    );
    assert.ok(
      proc2Result.accumulated >= 105,
      `Accumulated active seconds after pause (${proc2Result.accumulated}s) must include running segment`,
    );
    assert.equal(
      proc2Result.reentry.lastCompletedStep,
      "Finished research in Process 2",
    );

    // -------------------------------------------------------------------------
    // INTERLUDE: Wall-clock time elapses while no process is running
    // Paused timer must NOT accrue time during this window.
    // -------------------------------------------------------------------------
    const accumulatedBeforeSleep = proc2Result.accumulated;
    const sleepStart = Date.now();
    while (Date.now() - sleepStart < 1200) {
      // Busy-wait 1.2s to simulate real-world clock time advancing between app sessions
    }

    // -------------------------------------------------------------------------
    // PROCESS 3: Fresh process boots while paused.
    // Confirms paused task did NOT accrue time during sleep.
    // Resumes task, tests idempotency of repeated resume, simulates work, finishes, and EXITS.
    // -------------------------------------------------------------------------
    const proc3Output = runChild(`
      const { taskStorage, getElapsedActiveSeconds } = await import('./src/lib/storage');

      const tasks = taskStorage.getAll();
      const task = tasks.find(t => t.id === '${taskId}');
      if (!task) throw new Error('Task not found on disk');

      // 1. Paused task must NOT have accrued any elapsed time while process was dead
      const elapsedWhilePaused = getElapsedActiveSeconds(task);
      const accumulatedWhilePaused = task.accumulatedActiveSeconds;

      // 2. Resume task
      const resumed = taskStorage.resumeTask(task.id);
      const segmentStart1 = resumed.activeSegmentStartedAt;

      // 3. Repeated resume: MUST be idempotent and not reset activeSegmentStartedAt
      const repeatedResume = taskStorage.resumeTask(task.id);
      const segmentStart2 = repeatedResume.activeSegmentStartedAt;

      // 4. Simulate running for 25 seconds in this segment
      const twentyFiveSecsAgo = new Date(Date.now() - 25000).toISOString();
      taskStorage.save({
        ...resumed,
        activeSegmentStartedAt: twentyFiveSecsAgo,
      });

      // 5. Finish task
      const finished = taskStorage.finishTask(task.id);

      console.log(JSON.stringify({
        elapsedWhilePaused,
        accumulatedWhilePaused,
        segmentStart1,
        segmentStart2,
        finishedStatus: finished.status,
        finalAccumulated: finished.accumulatedActiveSeconds,
        hasCompletedAt: Boolean(finished.completedAt),
        activeSegmentCleared: finished.activeSegmentStartedAt === null
      }));
    `);

    const proc3Result = JSON.parse(proc3Output);

    // Verify paused timer did not accrue time during the 1.2s interlude
    assert.equal(
      proc3Result.accumulatedWhilePaused,
      accumulatedBeforeSleep,
      "Accumulated time must remain identical across cold restart while paused",
    );
    assert.equal(
      proc3Result.elapsedWhilePaused,
      accumulatedBeforeSleep,
      "Elapsed time must equal accumulated time when paused",
    );

    // Verify resume idempotency
    assert.equal(
      proc3Result.segmentStart1,
      proc3Result.segmentStart2,
      "Repeated resume must not overwrite activeSegmentStartedAt",
    );

    // Verify finished state
    assert.equal(proc3Result.finishedStatus, "finished");
    assert.ok(
      proc3Result.hasCompletedAt,
      "Finished task must have completedAt timestamp",
    );
    assert.ok(
      proc3Result.activeSegmentCleared,
      "Active segment must be null after finish",
    );
    assert.ok(
      proc3Result.finalAccumulated >= accumulatedBeforeSleep + 25,
      `Final accumulated time (${proc3Result.finalAccumulated}s) must include resumed segment (>= ${accumulatedBeforeSleep + 25}s)`,
    );
  } finally {
    // Cleanup temporary test file from disk
    if (fs.existsSync(storageFilePath)) {
      fs.unlinkSync(storageFilePath);
    }
  }
});
