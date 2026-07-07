// lib/platform/local/task_repository_impl.dart
//
// PLATFORM LAYER. Implements the domain TaskRepository against Drift. This is
// the only place that knows the local DB is Drift — Executive and Presentation
// depend on the interface in lib/domain/task_repository.dart, never on this.
//
// Writes are local-first (§12.3): every save() commits to Drift immediately
// and unconditionally, then enqueues a best-effort Google-mirror op. Capture
// must never fail because the network did.

import 'dart:convert';

import '../../domain/task.dart';
import '../../domain/task_repository.dart';
import 'database.dart';

class DriftTaskRepository implements TaskRepository {
  final AppDatabase _db;

  DriftTaskRepository(this._db);

  @override
  Future<List<Task>> openTasks() => _db.openTasks();

  @override
  Stream<List<Task>> watchOpenTasks() => _db.watchOpenTasks();

  @override
  Future<Task?> byId(String id) async {
    final all = await _db.openTasks();
    try {
      return all.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(Task task) async {
    final now = DateTime.now();
    final toWrite = task.copyWith(updatedAt: now, lastTouchedAt: now);

    // 1. Local write, unconditional — this is the source of truth (§3 v1.4).
    await _db.upsertTask(toWrite);

    // 2. Best-effort Google mirror — only the subset Google Tasks can hold
    //    (§12.3): title/notes(unused for now)/due/status. Extended fields
    //    (energy, priority, snapRef, confirmed, estimatedMinutes) never leave
    //    the local DB.
    await _enqueueMirror(toWrite);
  }

  @override
  Future<void> complete(String id) async {
    final t = await byId(id);
    if (t == null) return;
    final now = DateTime.now();
    await _db.upsertTask(t.copyWith(
      status: TaskStatus.complete,
      completedAt: now,
      lastTouchedAt: now,
      updatedAt: now,
    ));
    await _enqueueMirror(t, op: SyncOp.update);
  }

  @override
  Future<List<Task>> untouchedFor({required int days}) =>
      _db.untouchedFor(days);

  @override
  Future<void> archive(String id) async {
    final t = await byId(id);
    if (t == null) return;
    final now = DateTime.now();
    // Archive by moving to 'paused' state — recoverable, just out of default views (§6).
    // Phase 3: full archiving support with dedicated state.
    await _db.upsertTask(t.copyWith(
      status: TaskStatus.paused,
      lastTouchedAt: now,
      updatedAt: now,
    ));
  }

  @override
  Future<void> touch(String id) async {
    final t = await byId(id);
    if (t == null) return;
    await _db.upsertTask(t.copyWith(lastTouchedAt: DateTime.now()));
  }

  @override
  Stream<int> watchCompletedTodayCount() => _db.watchCompletedTodayCount();

  Future<void> _enqueueMirror(Task t, {SyncOp op = SyncOp.create}) async {
    final payload = {
      'title': t.title,
      'due': t.due?.toIso8601String(),
      'status': t.status.name,
      'googleTaskId': t.googleTaskId,
    };
    await _db.into(_db.syncQueue).insert(
          SyncQueueCompanion.insert(
            taskId: t.id,
            op: op,
            payloadJson: jsonEncode(payload),
            createdAt: DateTime.now(),
          ),
        );
    // NOTE(integration): a separate sync worker drains SyncQueue against
    // googleapis Tasks when online (fast-follow per §12.2) — not part of the
    // phase-1 spine. Local-first means the app is fully usable with this
    // queue never draining at all.
  }
}
