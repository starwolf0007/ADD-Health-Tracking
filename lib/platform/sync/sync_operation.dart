// lib/platform/sync/sync_operation.dart
//
// Domain model for a pending Google Tasks mirror operation.
// These live in the SyncQueue Drift table and are processed by
// GoogleTasksSyncService during WorkManager flushes.

import 'package:uuid/uuid.dart';

enum SyncOperationType {
  /// New task — push to Google Tasks, store returned googleTaskId.
  create,

  /// Title or notes changed — update the remote record.
  update,

  /// Task marked complete locally — mark complete on Google Tasks.
  complete,

  /// Task deleted locally — delete from Google Tasks if synced.
  delete,
}

class SyncOperation {
  final String id;
  final SyncOperationType type;
  final String taskId;

  /// Snapshot of title at enqueue time (used for create/update).
  final String? taskTitle;

  /// Snapshot of notes at enqueue time (used for create/update).
  final String? taskNotes;

  /// Remote Google Task ID — null if not yet synced (i.e., create pending).
  final String? googleTaskId;

  final int retryCount;
  final DateTime createdAt;

  const SyncOperation({
    required this.id,
    required this.type,
    required this.taskId,
    this.taskTitle,
    this.taskNotes,
    this.googleTaskId,
    this.retryCount = 0,
    required this.createdAt,
  });

  factory SyncOperation.forCreate({
    required String taskId,
    required String taskTitle,
    String? taskNotes,
  }) {
    return SyncOperation(
      id: const Uuid().v4(),
      type: SyncOperationType.create,
      taskId: taskId,
      taskTitle: taskTitle,
      taskNotes: taskNotes,
      createdAt: DateTime.now(),
    );
  }

  factory SyncOperation.forUpdate({
    required String taskId,
    required String taskTitle,
    String? taskNotes,
    String? googleTaskId,
  }) {
    return SyncOperation(
      id: const Uuid().v4(),
      type: SyncOperationType.update,
      taskId: taskId,
      taskTitle: taskTitle,
      taskNotes: taskNotes,
      googleTaskId: googleTaskId,
      createdAt: DateTime.now(),
    );
  }

  factory SyncOperation.forComplete({
    required String taskId,
    String? googleTaskId,
  }) {
    return SyncOperation(
      id: const Uuid().v4(),
      type: SyncOperationType.complete,
      taskId: taskId,
      googleTaskId: googleTaskId,
      createdAt: DateTime.now(),
    );
  }

  factory SyncOperation.forDelete({
    required String taskId,
    String? googleTaskId,
  }) {
    return SyncOperation(
      id: const Uuid().v4(),
      type: SyncOperationType.delete,
      taskId: taskId,
      googleTaskId: googleTaskId,
      createdAt: DateTime.now(),
    );
  }
}
