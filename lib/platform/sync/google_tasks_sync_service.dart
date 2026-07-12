// lib/platform/sync/google_tasks_sync_service.dart
//
// Orchestrates flushing the local sync queue to Google Tasks.
//
// Auth-gated design:
//   • Checks FlutterSecureStorage for a Google Tasks OAuth token.
//   • If no token found, returns immediately — queue remains pending.
//     This means the entire sync layer is wired up and running but
//     completely dormant until the user connects Google Tasks.
//   • When OAuth is implemented (phase 3+), the token write is the
//     only change needed to activate sync.
//
// API stubs:
//   All Google Tasks API calls are stubbed with TODO markers. The
//   architecture, error handling, and retry logic are complete so
//   that wiring in the real googleapis package is a surgical change.
//
// Retry policy:
//   • Each failed op increments retryCount in the DB.
//   • After 5 retries the op is marked 'failed' and ignored.
//   • WorkManager runs flush() every 4 hours (neuroflow.sync_flush).
//   • A fresh app launch also enqueues a flush via BackgroundScheduler.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:neuroflow/platform/sync/sync_operation.dart';
import 'package:neuroflow/platform/sync/sync_queue_repository.dart';

const _kGoogleTasksToken = 'neuroflow_google_tasks_token';
const _kGoogleTasksListId = 'neuroflow_google_tasks_list_id';

class GoogleTasksSyncService {
  static const _storage = FlutterSecureStorage();

  final SyncQueueRepository _queue;

  GoogleTasksSyncService(this._queue);

  /// Flush pending sync ops to Google Tasks.
  /// Safe to call from any isolate — reads its own DB connection via _queue.
  Future<void> flush() async {
    // 1. Auth gate — if no token, nothing to do.
    final token = await _storage.read(key: _kGoogleTasksToken);
    if (token == null || token.isEmpty) {
      // User hasn't connected Google Tasks yet. Queue stays warm.
      return;
    }

    final listId = await _storage.read(key: _kGoogleTasksListId) ?? '@default';
    final ops = await _queue.fetchPending(limit: 50);

    for (final op in ops) {
      try {
        await _processOp(op, token: token, listId: listId);
        await _queue.markDone(op.id);
      } catch (_) {
        await _queue.incrementRetry(op.id);
      }
    }

    // Housekeeping — purge old done entries.
    await _queue.clearCompleted();
  }

  Future<void> _processOp(
    SyncOperation op, {
    required String token,
    required String listId,
  }) async {
    switch (op.type) {
      case SyncOperationType.create:
        await _createRemoteTask(op, token: token, listId: listId);
        break;
      case SyncOperationType.update:
        if (op.googleTaskId == null) return; // not yet synced, skip
        await _updateRemoteTask(op, token: token, listId: listId);
        break;
      case SyncOperationType.complete:
        if (op.googleTaskId == null) return;
        await _completeRemoteTask(op, token: token, listId: listId);
        break;
      case SyncOperationType.delete:
        if (op.googleTaskId == null) return;
        await _deleteRemoteTask(op, token: token, listId: listId);
        break;
    }
  }

  // ----------------------------------------------------------------
  // API stubs — replace with `googleapis` package calls in phase 3.
  // ----------------------------------------------------------------

  Future<void> _createRemoteTask(
    SyncOperation op, {
    required String token,
    required String listId,
  }) async {
    // TODO(sync/phase3): POST /tasks/v1/lists/{listId}/tasks
    // Body: { title: op.taskTitle, notes: op.taskNotes }
    // On success: store response.id as googleTaskId in Tasks table
    //   await db.setGoogleTaskId(op.taskId, response.id);
    throw UnimplementedError('Google Tasks API not yet wired');
  }

  Future<void> _updateRemoteTask(
    SyncOperation op, {
    required String token,
    required String listId,
  }) async {
    // TODO(sync/phase3): PATCH /tasks/v1/lists/{listId}/tasks/{googleTaskId}
    // Body: { title: op.taskTitle, notes: op.taskNotes }
    throw UnimplementedError('Google Tasks API not yet wired');
  }

  Future<void> _completeRemoteTask(
    SyncOperation op, {
    required String token,
    required String listId,
  }) async {
    // TODO(sync/phase3): PATCH /tasks/v1/lists/{listId}/tasks/{googleTaskId}
    // Body: { status: 'completed' }
    throw UnimplementedError('Google Tasks API not yet wired');
  }

  Future<void> _deleteRemoteTask(
    SyncOperation op, {
    required String token,
    required String listId,
  }) async {
    // TODO(sync/phase3): DELETE /tasks/v1/lists/{listId}/tasks/{googleTaskId}
    throw UnimplementedError('Google Tasks API not yet wired');
  }

  // ----------------------------------------------------------------
  // Auth helpers (phase 3)
  // ----------------------------------------------------------------

  /// Store OAuth token after Google sign-in — activates sync.
  static Future<void> saveToken(String token) =>
      _storage.write(key: _kGoogleTasksToken, value: token);

  /// Clear token on sign-out — deactivates sync.
  static Future<void> clearToken() => _storage.delete(key: _kGoogleTasksToken);

  /// Whether the user has connected Google Tasks.
  static Future<bool> isConnected() async {
    final token = await _storage.read(key: _kGoogleTasksToken);
    return token != null && token.isNotEmpty;
  }
}
