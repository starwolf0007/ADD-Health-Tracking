// lib/platform/sync/sync_queue_repository.dart
//
// Interface for the Google Tasks sync queue.
// Drift implementation lives in sync_queue_repository_impl.dart.

import 'package:neuroflow/platform/sync/sync_operation.dart';

abstract class SyncQueueRepository {
  /// Add a new operation to the queue.
  Future<void> enqueue(SyncOperation op);

  /// Fetch up to [limit] pending operations, oldest first.
  Future<List<SyncOperation>> fetchPending({int limit = 50});

  /// Mark an operation as successfully synced.
  Future<void> markDone(String operationId);

  /// Increment retry count. After 5 retries the op is marked 'failed'.
  Future<void> incrementRetry(String operationId);

  /// Housekeeping — remove all done operations.
  Future<void> clearCompleted();
}
