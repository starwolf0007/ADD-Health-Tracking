// lib/platform/sync/google_sync_engine_impl.dart

import 'dart:async';
import 'package:neuroflow/domain/google/sync_engine.dart';
import 'package:neuroflow/platform/sync/sync_queue_repository.dart';
import 'package:neuroflow/platform/sync/sync_operation.dart';

class GoogleSyncEngineImpl implements SyncEngine {
  final SyncQueueRepository _queue;
  final _progressController = StreamController<SyncProgress>.broadcast();
  bool _isRunning = false;

  GoogleSyncEngineImpl(this._queue);

  @override
  Stream<SyncProgress> get progress => _progressController.stream;

  @override
  Future<void> flush() async {
    if (_isRunning) return;
    _isRunning = true;

    try {
      _emit(const SyncProgress(phase: SyncPhase.running));

      final pending = await _queue.fetchPending(limit: 50);
      if (pending.isEmpty) {
        _emit(const SyncProgress(phase: SyncPhase.idle));
        return;
      }

      int processed = 0;
      for (final op in pending) {
        processed++;
        _emit(SyncProgress(
          phase: SyncPhase.running,
          totalItems: pending.length,
          processedItems: processed,
          currentItemLabel: 'Processing item $processed of ${pending.length}',
        ));

        try {
          await _processOperation(op);
          await _queue.markDone(op.id);
        } catch (e) {
          await _queue.incrementRetry(op.id);
        }
      }

      await _queue.clearCompleted();
      _emit(const SyncProgress(phase: SyncPhase.idle));
    } catch (e) {
      _emit(const SyncProgress(phase: SyncPhase.error));
    } finally {
      _isRunning = false;
    }
  }

  @override
  Future<void> syncService(String serviceName) async {
    // Service-specific logic would be filtered here in a full implementation.
    await flush();
  }

  @override
  Future<void> resolveConflict(
      String entityId, dynamic local, dynamic remote) async {
    // TODO: Implement default conflict resolution (e.g., local wins or most recent wins).
  }

  Future<void> _processOperation(SyncOperation op) async {
    // This is where individual SyncProviders would be called.
    // In Sprint 1, we only build the foundation, so this is a NO-OP or log.
  }

  void _emit(SyncProgress p) => _progressController.add(p);

  void dispose() {
    _progressController.close();
  }
}
