// lib/domain/task.dart
//
// Pure domain model — no Flutter, no Drift, no Riverpod.
//
// PHASE 2 — LIVING-STATE MODEL (schema v3).
// Tasks are alive, not binary. The 7-state machine replaces the old
// {pending, completed, skipped}:
//
//   notStarted → preparing → inProgress → paused → blocked → checkpoint → complete
//
// "Tasks don't fail. They pause." The Re-Entry Card (Phase 2) reads a paused
// task's `pausedStep` + `pausedNote` to reconstruct exactly where momentum
// was lost. `pausedAt` orders the "what should I return to" list.
//
// BACKWARD COMPATIBILITY: the v2→v3 migration maps legacy string states:
//   'pending'   → notStarted
//   'completed' → complete
//   'skipped'   → blocked   (a skipped task was stopped, not finished —
//                            recoverable, not failed)

import 'package:uuid/uuid.dart';

enum EnergyLevel { low, medium, high }

/// The living-state machine. Stored by stable string key, never raw index.
enum TaskState {
  notStarted,
  preparing,
  inProgress,
  paused,
  blocked,
  checkpoint,
  complete,
}

extension TaskStateX on TaskState {
  String get storageKey => switch (this) {
        TaskState.notStarted => 'not_started',
        TaskState.preparing => 'preparing',
        TaskState.inProgress => 'in_progress',
        TaskState.paused => 'paused',
        TaskState.blocked => 'blocked',
        TaskState.checkpoint => 'checkpoint',
        TaskState.complete => 'complete',
      };

  static TaskState fromStorage(String s) => switch (s) {
        'not_started' => TaskState.notStarted,
        'preparing' => TaskState.preparing,
        'in_progress' => TaskState.inProgress,
        'paused' => TaskState.paused,
        'blocked' => TaskState.blocked,
        'checkpoint' => TaskState.checkpoint,
        'complete' => TaskState.complete,
        // Legacy v2 values (migration also rewrites these in-place):
        'pending' => TaskState.notStarted,
        'completed' => TaskState.complete,
        'skipped' => TaskState.blocked,
        _ => TaskState.notStarted,
      };

  String get label => switch (this) {
        TaskState.notStarted => 'Not started',
        TaskState.preparing => 'Preparing',
        TaskState.inProgress => 'In progress',
        TaskState.paused => 'Paused',
        TaskState.blocked => 'Blocked',
        TaskState.checkpoint => 'Checkpoint',
        TaskState.complete => 'Complete',
      };

  /// "Open" = still needs attention (surfaces in the plan / pending list).
  bool get isOpen => this != TaskState.complete;
  bool get isComplete => this == TaskState.complete;

  /// Active = a transition state that belongs on the Today plan alongside
  /// not-started work (preparing / in-progress / checkpoint). These states
  /// were previously falling out of the plan streams (fixed in v3).
  bool get isActive =>
      this == TaskState.preparing ||
      this == TaskState.inProgress ||
      this == TaskState.checkpoint;

  /// Interrupted — the Re-Entry Card's domain.
  bool get isInterrupted =>
      this == TaskState.paused || this == TaskState.blocked;
  bool get isCheckpoint => this == TaskState.checkpoint;

  /// Legal next states — guards invalid transitions, drives UI affordances.
  Set<TaskState> get allowedNext => switch (this) {
        TaskState.notStarted => {TaskState.preparing, TaskState.inProgress},
        TaskState.preparing => {TaskState.inProgress, TaskState.paused},
        TaskState.inProgress => {
            TaskState.paused,
            TaskState.blocked,
            TaskState.checkpoint,
            TaskState.complete,
          },
        TaskState.paused => {TaskState.inProgress, TaskState.blocked},
        TaskState.blocked => {TaskState.inProgress},
        TaskState.checkpoint => {TaskState.inProgress, TaskState.complete},
        TaskState.complete => <TaskState>{}, // terminal
      };
}

class Task {
  final String id;
  final String title;
  final String? notes;
  final EnergyLevel energy;
  final TaskState state;
  final DateTime createdAt;
  final DateTime? dueDate;
  final bool isQuickWin;
  final int? estimatedMinutes;
  final DateTime? completedAt;

  // --- Living-state / Re-Entry metadata (Phase 2) ---
  final DateTime? pausedAt; // orders the "what to return to" list
  final String? pausedStep; // where you stopped, in your words
  final String? pausedNote; // optional freeform re-entry hint

  const Task({
    required this.id,
    required this.title,
    this.notes,
    required this.energy,
    this.state = TaskState.notStarted,
    required this.createdAt,
    this.dueDate,
    this.isQuickWin = false,
    this.estimatedMinutes,
    this.completedAt,
    this.pausedAt,
    this.pausedStep,
    this.pausedNote,
  });

  factory Task.create({
    required String title,
    String? notes,
    EnergyLevel energy = EnergyLevel.medium,
    DateTime? dueDate,
    bool isQuickWin = false,
    int? estimatedMinutes,
  }) {
    return Task(
      id: const Uuid().v4(),
      title: title,
      notes: notes,
      energy: energy,
      state: TaskState.notStarted,
      createdAt: DateTime.now(),
      dueDate: dueDate,
      isQuickWin: isQuickWin,
      estimatedMinutes: estimatedMinutes,
    );
  }

  Task copyWith({
    String? title,
    String? notes,
    EnergyLevel? energy,
    TaskState? state,
    DateTime? dueDate,
    bool? isQuickWin,
    int? estimatedMinutes,
    DateTime? completedAt,
    DateTime? pausedAt,
    String? pausedStep,
    String? pausedNote,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      energy: energy ?? this.energy,
      state: state ?? this.state,
      createdAt: createdAt,
      dueDate: dueDate ?? this.dueDate,
      isQuickWin: isQuickWin ?? this.isQuickWin,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      completedAt: completedAt ?? this.completedAt,
      pausedAt: pausedAt ?? this.pausedAt,
      pausedStep: pausedStep ?? this.pausedStep,
      pausedNote: pausedNote ?? this.pausedNote,
    );
  }

  bool get isOpen => state.isOpen;
  bool get isComplete => state.isComplete;
  bool get isInterrupted => state.isInterrupted;

  /// Legacy alias — call sites that still read `isPending`. Unstarted is the
  /// closest equivalent. Kept so the migration doesn't ripple through the UI.
  bool get isPending => state == TaskState.notStarted;

  /// Transition helper that keeps pause/complete metadata consistent.
  ///
  /// Resuming or advancing an interrupted task (any non-pause, non-complete
  /// target) explicitly clears the re-entry metadata so a paused → inProgress
  /// hop never carries a stale `pausedAt` / `pausedStep` / `pausedNote`.
  Task transitionTo(TaskState next, {String? step, String? note}) {
    switch (next) {
      case TaskState.paused:
      case TaskState.blocked:
        // Build explicitly so passing no step/note *replaces* (clears) any
        // prior re-entry context — copyWith's `??` would otherwise retain a
        // stale pausedStep/pausedNote across a paused → blocked hop.
        return Task(
          id: id,
          title: title,
          notes: notes,
          energy: energy,
          state: next,
          createdAt: createdAt,
          dueDate: dueDate,
          isQuickWin: isQuickWin,
          estimatedMinutes: estimatedMinutes,
          completedAt: completedAt,
          pausedAt: DateTime.now(),
          pausedStep: step,
          pausedNote: note,
        );
      case TaskState.complete:
        return copyWith(state: next, completedAt: DateTime.now());
      default:
        return Task(
          id: id,
          title: title,
          notes: notes,
          energy: energy,
          state: next,
          createdAt: createdAt,
          dueDate: dueDate,
          isQuickWin: isQuickWin,
          estimatedMinutes: estimatedMinutes,
          completedAt: completedAt,
          pausedAt: null,
          pausedStep: null,
          pausedNote: null,
        );
    }
  }
}
