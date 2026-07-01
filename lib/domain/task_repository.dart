// lib/domain/task_repository.dart
//
// The boundary. Executive and Presentation depend on THIS interface, never on
// Drift or Google. The Platform layer provides the implementation. This is what
// keeps persistence swappable and the upper layers testable.

import 'task.dart';

abstract class TaskRepository {
  /// All open tasks (inbox/today/scheduled), source-of-truth = local DB.
  Future<List<Task>> openTasks();

  /// Reactive stream for the UI.
  Stream<List<Task>> watchOpenTasks();

  Future<Task?> byId(String id);

  /// Create or update. Writes locally first (offline-first, §12.3), then
  /// enqueues a Google mirror op for the syncable subset.
  Future<void> save(Task task);

  /// Mark done — sets completedAt + status, touches lastTouchedAt.
  Future<void> complete(String id);

  /// Sweep support (§6): tasks open and untouched for >= [days].
  Future<List<Task>> untouchedFor({required int days});

  /// Archive (recoverable), never hard-delete from a sweep.
  Future<void> archive(String id);

  /// Any user interaction bumps lastTouchedAt so the sweep clock resets.
  Future<void> touch(String id);

  /// Completions today — drives the Today "heartbeat" line (§13). Added
  /// alongside the Presentation build: the heartbeat needs a real ratio, not
  /// a placeholder, and nothing upstream produced one yet.
  Stream<int> watchCompletedTodayCount();
}
