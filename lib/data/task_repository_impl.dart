// lib/data/task_repository_impl.dart
//
// Drift-backed implementation of TaskRepository.
// Local Drift is the source of truth (§12.3).
// Google Tasks is the mirror / async sync queue — never reads from it.

import 'package:drift/drift.dart';

import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/platform/sync/sync_operation.dart';
import 'package:neuroflow/platform/sync/sync_queue_repository.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/task_repository.dart';

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
      state: TaskStateX.fromStorage(row.status),
      createdAt: row.createdAt,
      dueDate: row.dueDate,
      isQuickWin: row.isQuickWin,
      estimatedMinutes: row.estimatedMinutes,
      completedAt: row.completedAt,
      pausedAt: row.pausedAt,
      pausedStep: row.pausedStep,
      pausedNote: row.pausedNote,
    );
  }

  TasksCompanion _taskToCompanion(Task task) {
    return TasksCompanion(
      id: Value(task.id),
      title: Value(task.title),
      notes: Value(task.notes),
      energy: Value(_energyToString(task.energy)),
      status: Value(task.state.storageKey),
      createdAt: Value(task.createdAt),
      dueDate: Value(task.dueDate),
      isQuickWin: Value(task.isQuickWin),
      estimatedMinutes: Value(task.estimatedMinutes),
      completedAt: Value(task.completedAt),
      pausedAt: Value(task.pausedAt),
      pausedStep: Value(task.pausedStep),
      pausedNote: Value(task.pausedNote),
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
  Stream<List<Task>> watchInterrupted() {
    return _db.watchInterrupted().map(
          (rows) => rows.map(_rowToTask).toList(),
        );
  }

  @override
  Stream<List<Task>> watchCompletedToday() {
    return _db.watchCompletedToday().map(
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
        await _syncQueue.enqueue(SyncOperation.forCreate(
          taskId: task.id,
          taskTitle: task.title,
          taskNotes: task.notes,
        ));
      } else {
        final googleTaskId = await _getGoogleTaskId(task.id);
        await _syncQueue.enqueue(SyncOperation.forUpdate(
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
      await _syncQueue.enqueue(SyncOperation.forComplete(
        taskId: id,
        googleTaskId: googleTaskId,
      ));
    }
  }

  @override
  Future<void> resume(String id) async {
    // Living-state transition — local only. Google Tasks mirrors title/notes/
    // completion, not the in_progress/paused lifecycle, so nothing to enqueue.
    await _db.resumeTask(id);
  }

  @override
  Future<void> delete(String id) async {
    final googleTaskId = await _getGoogleTaskId(id);
    await _db.deleteTask(id);
    if (_syncQueue != null && googleTaskId != null) {
      await _syncQueue.enqueue(SyncOperation.forDelete(
        taskId: id,
        googleTaskId: googleTaskId,
      ));
    }
  }

  @override
  Future<Task?> getById(String id) async {
    final row = await (_db.select(_db.tasks)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _rowToTask(row);
  }

  // ------------------------------------------------------------------
  // Sync helpers
  // ------------------------------------------------------------------

  Future<bool> _isNewTask(String id) async {
    final row = await (_db.select(_db.tasks)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null;
  }

  Future<String?> _getGoogleTaskId(String id) async {
    final row = await (_db.select(_db.tasks)
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

}
