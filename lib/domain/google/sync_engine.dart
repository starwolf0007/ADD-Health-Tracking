// lib/domain/google/sync_engine.dart

enum SyncPhase { idle, running, cleanup, error }

class SyncProgress {
  final SyncPhase phase;
  final int totalItems;
  final int processedItems;
  final String? currentItemLabel;
  final String? errorMessage;

  const SyncProgress({
    required this.phase,
    this.totalItems = 0,
    this.processedItems = 0,
    this.currentItemLabel,
    this.errorMessage,
  });

  double get percent => totalItems == 0 ? 0 : processedItems / totalItems;
}

class SyncEngineException implements Exception {
  final int failedOperationCount;
  final Object cause;

  const SyncEngineException(this.failedOperationCount, this.cause);

  @override
  String toString() =>
      'Sync failed for $failedOperationCount operation(s): $cause';
}

abstract class SyncEngine {
  /// Stream of current sync progress.
  Stream<SyncProgress> get progress;

  /// Full synchronization across all enabled services.
  Future<void> flush();

  /// Synchronize a specific service.
  Future<void> syncService(String serviceName);

  /// Hook for conflict resolution.
  /// To be implemented by specific sync providers.
  Future<void> resolveConflict(String entityId, dynamic local, dynamic remote);
}
