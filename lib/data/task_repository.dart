// lib/data/task_repository.dart
//
// Abstract repository interface. Executive layer depends only on this;
// Drift implementation is injected via Riverpod (see providers.dart).

import '../domain/task.dart';

abstract class TaskRepository {
  /// All pending tasks, ordered by energy ascending (low first).
  Stream<List<Task>> watchPending();

  /// Count of tasks completed today — used by the heartbeat line.
  Stream<int> watchCompletedTodayCount();

  Future<void> save(Task task);
  Future<void> markComplete(String id);
  Future<void> delete(String id);
}
