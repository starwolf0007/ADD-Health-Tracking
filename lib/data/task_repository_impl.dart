// lib/data/task_repository_impl.dart
//
// Drift-backed implementation of TaskRepository.
// Local Drift is the source of truth (§12.3).
// Google Tasks is the mirror / async sync queue — never reads from it.

import 'package:drift/drift.dart';

import '../domain/task.dart';
import '../platform/sync/sync_operation.dart';
import '../platform/sync/sync_queue_repository.dart';
import 'database.dart';
import 'task_repository.dart';

class DriftTaskRepository implements TaskRepository {
  final AppDatabase _db;
  final SyncQueueRepository? _syncQueue;

  /// [syncQueue] is optional — passing null disables sync enqueueing.
  /// The WorkManager isolate omits it; the main isolate supplies it.
  DriftTaskRepository(this._db, {SyncQueueRepository? syncQueue})
      : _syncQueue = syncQueue;

  // ------------------------------------------------------------------
  // Mappers
  // ------------------------------------------------------------------

  Task _rowToTask(TaskRow row) {
    return Task(
      id: row.id,
      title: row.title,
      notes: row.notes,
      energy: _energyFromString(row.energy),
      status: _statusFromString(row.status),
      createdAt: row.createdAt,
      dueDate: row.dueDate,
      completedAt: row.completedAt,
      isQuickWin: row.isQuickWin,
    );
  }

  TasksCompanion _taskToCompanion(Task task) {
    return TasksCompanion(
      id: Value(task.id),
      title: Value(task.title),
      notes: Value(task.notes),
      energy: Value(_energyToString(task.energy)),
      status: Value(_statusToString(task.status)),
      createdAt: Value(task.createdAt),
      dueDate: Value(task.dueDate),
      completedAt: Value(task.completedAt),
      isQuickWin: Value(task.isQuickWin),
    );
  }

  // ------------------------------------------------------------------
  // Interface implementation
  // ------------------------------------------------------------------

  @override
  Stream<List<Task>> watchPending() {
    return _db.watchPendingByEnergyAsc().map(
          (rows) => rows.map(_rowToTask).toList(),
        );
  }

  @override
  Stream<int> watchCompletedTodayCount() {
    return _db.watchCompletedTodayCount();
  }

  @override
  Future<void> save(Task task) async {
    final isNew = await _isNewTask(task.id);
    await _db.upsertTask(_taskToCompanion(task));
    if (_syncQueue != null) {
      if (isNew) {
        await _syncQueue!.enqueue(SyncOperation.forCreate(
          taskId: task.id,
          taskTitle: task.title,
          taskNotes: task.notes,
        ));
      } else {
        final googleTaskId = await _getGoogleTaskId(task.id);
        await _syncQueue!.enqueue(SyncOperation.forUpdate(
          taskId: task.id,
          taskTitle: task.title,
          taskNotes: task.notes,
          googleTaskId: googleTaskId,
        ));
      }
    }
  }

  @override
  Future<void> markComplete(String id) async {
    final googleTaskId = await _getGoogleTaskId(id);
    await _db.markComplete(id);
    if (_syncQueue != null) {
      await _syncQueue!.enqueue(SyncOperation.forComplete(
        taskId: id,
        googleTaskId: googleTaskId,
      ));
    }
  }

  @override
  Future<void> delete(String id) async {
    final googleTaskId = await _getGoogleTaskId(id);
    await _db.deleteTask(id);
    if (_syncQueue != null && googleTaskId != null) {
      await _syncQueue!.enqueue(SyncOperation.forDelete(
        taskId: id,
        googleTaskId: googleTaskId,
      ));
    }
  }

  // ------------------------------------------------------------------
  // Sync helpers
  // ------------------------------------------------------------------

  Future<bool> _isNewTask(String id) async {
    final row = await (select(_db.tasks)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null;
  }

  Future<String?> _getGoogleTaskId(String id) async {
    final row = await (select(_db.tasks)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row?.googleTaskId;
  }

  // ------------------------------------------------------------------
  // String converters
  // ------------------------------------------------------------------

  EnergyLevel _energyFromString(String s) {
    switch (s) {
      case 'low':
        return EnergyLevel.low;
      case 'high':
        return EnergyLevel.high;
      default:
        return EnergyLevel.medium;
    }
  }

  String _energyToString(EnergyLevel e) {
    switch (e) {
      case EnergyLevel.low:
        return 'low';
      case EnergyLevel.high:
        return 'high';
      case EnergyLevel.medium:
        return 'medium';
    }
  }

  /// Convert stored string to 7-state TaskStatus model (Phase 2 STAGE 2).
  /// Handles legacy values from Phase 1 for backward compatibility.
  TaskStatus _statusFromString(String s) {
    switch (s) {
      // Legacy values (Phase 1) — map to new model
      case 'pending':
        return TaskStatus.notStarted; // default for legacy tasks
      case 'completed':
        return TaskStatus.complete;
      case 'skipped':
        return TaskStatus.paused; // archive via paused state
      // New values (Phase 2 STAGE 2)
      case 'notStarted':
        return TaskStatus.notStarted;
      case 'preparing':
        return TaskStatus.preparing;
      case 'inProgress':
        return TaskStatus.inProgress;
      case 'paused':
        return TaskStatus.paused;
      case 'blocked':
        return TaskStatus.blocked;
      case 'checkpoint':
        return TaskStatus.checkpoint;
      case 'complete':
        return TaskStatus.complete;
      default:
        return TaskStatus.notStarted; // safe default
    }
  }

  /// Convert 7-state TaskStatus to string for persistence (Phase 2 STAGE 2).
  String _statusToString(TaskStatus s) {
    switch (s) {
      case TaskStatus.notStarted:
        return 'notStarted';
      case TaskStatus.preparing:
        return 'preparing';
      case TaskStatus.inProgress:
        return 'inProgress';
      case TaskStatus.paused:
        return 'paused';
      case TaskStatus.blocked:
        return 'blocked';
      case TaskStatus.checkpoint:
        return 'checkpoint';
      case TaskStatus.complete:
        return 'complete';
    }
  }
}
