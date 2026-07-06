// lib/data/task_repository_impl.dart
//
// Drift-backed implementation of TaskRepository.
// Local Drift is the source of truth (§12.3).
// Google Tasks is the mirror / async sync queue — never reads from it.

import '../domain/task.dart';
import 'database.dart';
import 'task_repository.dart';
import 'package:drift/drift.dart';

class DriftTaskRepository implements TaskRepository {
  final AppDatabase _db;

  DriftTaskRepository(this._db);

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
  Stream<int> watchCompletedTodayCount() {
    return _db.watchCompletedTodayCount();
  }

  @override
  Future<void> save(Task task) async {
    await _db.upsertTask(_taskToCompanion(task));
    // TODO(sync): enqueue Google Tasks mirror update
  }

  @override
  Future<void> markComplete(String id) async {
    await _db.markComplete(id);
    // TODO(sync): enqueue Google Tasks completion update
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
  Future<void> delete(String id) async {
    await _db.deleteTask(id);
    // TODO(sync): enqueue Google Tasks delete
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
