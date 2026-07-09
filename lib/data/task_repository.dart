// lib/data/task_repository.dart
//
// Abstract repository interface. Executive layer depends only on this;
// Drift implementation is injected via Riverpod (see providers.dart).

import 'package:neuroflow/domain/task.dart';

abstract class TaskRepository {
  /// Active plan tasks (open, non-interrupted), ordered by energy ascending.
  Stream<List<Task>> watchPending();

  /// Interrupted (paused / blocked) tasks — the Re-Entry Card's source.
  Stream<List<Task>> watchInterrupted();

  /// Tasks completed today, as objects — for the timeline projection.
  Stream<List<Task>> watchCompletedToday();

  /// Count of tasks completed today — used by the heartbeat line.
  Stream<int> watchCompletedTodayCount();

  Future<void> save(Task task);
  Future<void> markComplete(String id);

  /// Resume an interrupted task to in-progress, clearing stale re-entry
  /// metadata (pausedAt / pausedStep / pausedNote).
  Future<void> resume(String id);

  Future<void> delete(String id);
  Future<Task?> getById(String id);
}
