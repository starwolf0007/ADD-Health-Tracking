// lib/platform/sync/sync_queue_repository_impl.dart
//
// Drift-backed SyncQueueRepository.

import 'package:drift/drift.dart';

import '../../data/database.dart';
import 'sync_operation.dart';
import 'sync_queue_repository.dart';

class DriftSyncQueueRepository implements SyncQueueRepository {
  final AppDatabase _db;

  DriftSyncQueueRepository(this._db);

  // ------------------------------------------------------------------
  // Mappers
  // ------------------------------------------------------------------

  SyncOperation _rowToOp(SyncQueueData row) {
    return SyncOperation(
      id: row.id,
      type: _typeFromString(row.operation),
      taskId: row.taskId,
      taskTitle: row.taskTitle,
      taskNotes: row.taskNotes,
      googleTaskId: row.googleTaskId,
      retryCount: row.retryCount,
      createdAt: row.createdAt,
    );
  }

  SyncQueueCompanion _opToCompanion(SyncOperation op) {
    return SyncQueueCompanion(
      id: Value(op.id),
      operation: Value(_typeToString(op.type)),
      taskId: Value(op.taskId),
      taskTitle: Value(op.taskTitle),
      taskNotes: Value(op.taskNotes),
      googleTaskId: Value(op.googleTaskId),
      status: const Value('pending'),
      retryCount: const Value(0),
      createdAt: Value(op.createdAt),
    );
  }

  // ------------------------------------------------------------------
  // Interface implementation
  // ------------------------------------------------------------------

  @override
  Future<void> enqueue(SyncOperation op) async {
    await _db.enqueueSyncOp(_opToCompanion(op));
  }

  @override
  Future<List<SyncOperation>> fetchPending({int limit = 50}) async {
    final rows = await _db.fetchPendingSyncOps(limit: limit);
    return rows.map(_rowToOp).toList();
  }

  @override
  Future<void> markDone(String operationId) =>
      _db.markSyncOpDone(operationId);

  @override
  Future<void> incrementRetry(String operationId) =>
      _db.incrementSyncRetry(operationId);

  @override
  Future<void> clearCompleted() => _db.clearDoneSyncOps();

  // ------------------------------------------------------------------
  // String converters
  // ------------------------------------------------------------------

  SyncOperationType _typeFromString(String s) {
    switch (s) {
      case 'create':
        return SyncOperationType.create;
      case 'update':
        return SyncOperationType.update;
      case 'complete':
        return SyncOperationType.complete;
      case 'delete':
        return SyncOperationType.delete;
      default:
        return SyncOperationType.update;
    }
  }

  String _typeToString(SyncOperationType t) {
    switch (t) {
      case SyncOperationType.create:
        return 'create';
      case SyncOperationType.update:
        return 'update';
      case SyncOperationType.complete:
        return 'complete';
      case SyncOperationType.delete:
        return 'delete';
    }
  }
}
