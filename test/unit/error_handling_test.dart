import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:neuroflow/domain/google/google_account.dart';
import 'package:neuroflow/domain/google/google_account_repository.dart';
import 'package:neuroflow/domain/google/google_auth_repository.dart';
import 'package:neuroflow/domain/google/google_connection_state.dart';
import 'package:neuroflow/domain/google/sync_engine.dart';
import 'package:neuroflow/platform/google/google_service_manager.dart';
import 'package:neuroflow/platform/sync/google_sync_engine_impl.dart';
import 'package:neuroflow/platform/sync/google_tasks_sync_service.dart';
import 'package:neuroflow/platform/sync/sync_operation.dart';
import 'package:neuroflow/platform/sync/sync_queue_repository.dart';

void main() {
  group('GoogleServiceManager', () {
    test('records and propagates sign-in failures', () async {
      final error = StateError('sign-in failed');
      final manager = GoogleServiceManager(
        _FakeGoogleAuthRepository(signInError: error),
        _FakeGoogleAccountRepository(),
      );

      await expectLater(manager.signIn(), throwsA(same(error)));
      expect(manager.currentState.status, GoogleConnectionStatus.failed);
      expect(manager.currentState.errorMessage, contains('sign-in failed'));
    });

    test('records and propagates token refresh failures', () async {
      final error = StateError('refresh failed');
      final manager = GoogleServiceManager(
        _FakeGoogleAuthRepository(refreshError: error),
        _FakeGoogleAccountRepository(),
      );

      await expectLater(manager.refreshToken(), throwsA(same(error)));
      expect(manager.currentState.status, GoogleConnectionStatus.expired);
      expect(manager.currentState.errorMessage, contains('refresh failed'));
    });
  });

  group('sync failures', () {
    test('Google Tasks flush retries invalid operations and reports failure',
        () async {
      final operation = SyncOperation.forUpdate(
        taskId: 'task-1',
        taskTitle: 'Missing remote ID',
      );
      final queue = _FakeSyncQueue([operation]);
      final service = GoogleTasksSyncService(
        queue,
        readSecureValue: (key) async => 'token',
      );

      await expectLater(
        service.flush(),
        throwsA(
          isA<SyncFlushException>().having(
              (error) => error.failedOperationCount, 'failure count', 1),
        ),
      );
      expect(queue.retriedIds, [operation.id]);
      expect(queue.doneIds, isEmpty);
      expect(queue.didClearCompleted, isTrue);
    });

    test('sync engine emits an error and propagates operation failures',
        () async {
      final operation = SyncOperation(
        id: 'operation-1',
        type: SyncOperationType.create,
        taskId: 'task-1',
        taskTitle: 'Task',
        createdAt: DateTime(2026),
      );
      final queue = _FakeSyncQueue(
        [operation],
        markDoneError: StateError('database unavailable'),
      );
      final engine = GoogleSyncEngineImpl(queue);
      final progress = <SyncProgress>[];
      final subscription = engine.progress.listen(progress.add);

      await expectLater(
        engine.flush(),
        throwsA(
          isA<SyncEngineException>().having(
              (error) => error.failedOperationCount, 'failure count', 1),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(progress.last.phase, SyncPhase.error);
      expect(progress.last.errorMessage, contains('database unavailable'));
      expect(queue.retriedIds, ['operation-1']);

      await subscription.cancel();
      engine.dispose();
    });
  });
}

class _FakeGoogleAuthRepository implements GoogleAuthRepository {
  final Object? signInError;
  final Object? refreshError;

  _FakeGoogleAuthRepository({
    this.signInError,
    this.refreshError,
  });

  @override
  Stream<GoogleAccount?> get onAccountChanged => const Stream.empty();

  @override
  Future<GoogleAccount?> get currentAccount async => null;

  @override
  Future<http.Client?> getAuthenticatedClient(List<String> scopes) async =>
      null;

  @override
  Future<void> refreshToken() async {
    if (refreshError != null) throw refreshError!;
  }

  @override
  Future<GoogleAccount?> signIn() async {
    if (signInError != null) throw signInError!;
    return null;
  }

  @override
  Future<GoogleAccount?> signInSilently() async => null;

  @override
  Future<void> signOut() async {}
}

class _FakeGoogleAccountRepository implements GoogleAccountRepository {
  @override
  Future<void> clearAccount() async {}

  @override
  Future<String?> getPersistedAccountId() async => null;

  @override
  Future<void> saveAccount(GoogleAccount account) async {}
}

class _FakeSyncQueue implements SyncQueueRepository {
  final List<SyncOperation> operations;
  final Object? markDoneError;
  final List<String> doneIds = [];
  final List<String> retriedIds = [];
  bool didClearCompleted = false;

  _FakeSyncQueue(
    this.operations, {
    this.markDoneError,
  });

  @override
  Future<void> clearCompleted() async {
    didClearCompleted = true;
  }

  @override
  Future<void> enqueue(SyncOperation op) async {}

  @override
  Future<List<SyncOperation>> fetchPending({int limit = 50}) async =>
      operations;

  @override
  Future<void> incrementRetry(String operationId) async {
    retriedIds.add(operationId);
  }

  @override
  Future<void> markDone(String operationId) async {
    if (markDoneError != null) throw markDoneError!;
    doneIds.add(operationId);
  }
}
