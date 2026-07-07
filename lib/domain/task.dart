// lib/domain/task.dart
//
// Pure domain model — no Flutter, no Drift, no Riverpod.
// Everything above this layer depends on Task; nothing here depends on anything.

import 'package:uuid/uuid.dart';

enum EnergyLevel { low, medium, high }

/// 7-state task lifecycle model — Phase 2 STAGE 2.
/// Enables progress tracking and ADHD-friendly state management.
///
/// State diagram:
///   notStarted → preparing → inProgress → paused → checkpoint → complete
///                                   ↓
///                              blocked (waiting external input)
///
/// See §2 in DECISIONS.md for design rationale.
enum TaskStatus {
  notStarted,  // Initial state when task is created
  preparing,   // User has begun thinking about the task (pre-execution)
  inProgress,  // Task is actively being worked on
  paused,      // User paused mid-execution (context switch, interruption)
  blocked,     // Task is blocked waiting for external input
  checkpoint,  // User completed a sub-phase (intermediate milestone)
  complete,    // Task is fully finished
}

class Task {
  final String id;
  final String title;
  final String? notes;
  final EnergyLevel energy;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final bool isQuickWin; // §QW — eligible for auto-mode Quick Wins list

  const Task({
    required this.id,
    required this.title,
    this.notes,
    required this.energy,
    this.status = TaskStatus.notStarted,
    required this.createdAt,
    this.dueDate,
    this.completedAt,
    this.isQuickWin = false,
  });

  factory Task.create({
    required String title,
    String? notes,
    EnergyLevel energy = EnergyLevel.medium,
    DateTime? dueDate,
    bool isQuickWin = false,
  }) {
    return Task(
      id: const Uuid().v4(),
      title: title,
      notes: notes,
      energy: energy,
      status: TaskStatus.notStarted,
      createdAt: DateTime.now(),
      dueDate: dueDate,
      isQuickWin: isQuickWin,
    );
  }

  Task copyWith({
    String? title,
    String? notes,
    EnergyLevel? energy,
    TaskStatus? status,
    DateTime? dueDate,
    DateTime? completedAt,
    bool? isQuickWin,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      energy: energy ?? this.energy,
      status: status ?? this.status,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      completedAt: completedAt ?? this.completedAt,
      isQuickWin: isQuickWin ?? this.isQuickWin,
    );
  }

  // -----------------------------------------------------------------------
  // Computed helpers — updated for 7-state model
  // -----------------------------------------------------------------------

  /// Task is still in work — includes states that aren't complete.
  /// Pending in the 7-state model = {notStarted, preparing, inProgress, paused, blocked, checkpoint}
  bool get isPending =>
      status != TaskStatus.complete;

  /// Task is fully finished.
  bool get isCompleted => status == TaskStatus.complete;

  /// Task is actively being worked on.
  bool get isInProgress => status == TaskStatus.inProgress;

  /// Task is paused (context switch, interruption).
  /// Used by re-entry card logic (Phase 3 STAGE 3).
  bool get isPaused => status == TaskStatus.paused;

  /// Task is blocked waiting for something external.
  bool get isBlocked => status == TaskStatus.blocked;
}
