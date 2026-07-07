// lib/domain/timeline_event.dart
//
// Pure domain model for timeline events — projection of tasks, routines, and mood logs
// into a chronological stream. Used by timelineProvider to build a unified activity feed.
//
// NO DATABASE TABLE — this is read-only, computed from existing tables via in-memory
// merging in the timelineProvider. See Timeline Rule §4 in DECISIONS.md.

import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// TimelineEventType — classification of all activity in the app
// ---------------------------------------------------------------------------

enum TimelineEventType {
  // Task lifecycle
  taskCreated,
  taskStarted,
  taskPaused,
  taskBlocked,
  taskCheckpoint,
  taskCompleted,

  // Routine lifecycle
  routineStarted,
  routineCompleted,

  // Habit check-ins
  habitChecked,

  // Mood logging
  moodLogged,
}

// ---------------------------------------------------------------------------
// TimelineEvent — abstract base for all timeline entries
// ---------------------------------------------------------------------------

abstract class TimelineEvent {
  /// Unique event identifier (for deduplication/equality).
  String get id;

  /// When the event occurred or was logged.
  DateTime get timestamp;

  /// Short title (e.g., "Completed Quick Grocery Run").
  String get title;

  /// Longer description or context (e.g., "Energy: medium").
  String get description;

  /// What kind of activity this was.
  TimelineEventType get type;
}

// ---------------------------------------------------------------------------
// TaskEvent — task lifecycle event
// ---------------------------------------------------------------------------

class TaskEvent implements TimelineEvent {
  @override
  final String id;

  @override
  final DateTime timestamp;

  final String taskId;
  final String taskTitle;
  final String? taskNotes;

  @override
  final TimelineEventType type;

  /// Status at event time (e.g., "In Progress").
  final String statusLabel;

  /// Energy level of the task (e.g., "Low").
  final String? energyLabel;

  TaskEvent({
    required this.taskId,
    required this.taskTitle,
    this.taskNotes,
    required this.timestamp,
    required this.type,
    required this.statusLabel,
    this.energyLabel,
  }) : id = 'task-$taskId-${type.name}-${timestamp.millisecondsSinceEpoch}';

  @override
  String get title => switch (type) {
    TimelineEventType.taskCreated => 'Created: $taskTitle',
    TimelineEventType.taskStarted => 'Started: $taskTitle',
    TimelineEventType.taskPaused => 'Paused: $taskTitle',
    TimelineEventType.taskBlocked => 'Blocked: $taskTitle',
    TimelineEventType.taskCheckpoint => 'Checkpoint: $taskTitle',
    TimelineEventType.taskCompleted => 'Completed: $taskTitle',
    _ => taskTitle,
  };

  @override
  String get description {
    final parts = <String>[];
    if (energyLabel != null) parts.add('Energy: $energyLabel');
    parts.add('Status: $statusLabel');
    if (taskNotes != null && taskNotes!.isNotEmpty) {
      parts.add('Notes: ${taskNotes!.substring(0, 50)}${taskNotes!.length > 50 ? '...' : ''}');
    }
    return parts.join(' • ');
  }
}

// ---------------------------------------------------------------------------
// RoutineEvent — routine lifecycle event
// ---------------------------------------------------------------------------

class RoutineEvent implements TimelineEvent {
  @override
  final String id;

  @override
  final DateTime timestamp;

  final String routineId;
  final String routineName;
  final int completedSteps;
  final int totalSteps;

  @override
  final TimelineEventType type;

  RoutineEvent({
    required this.routineId,
    required this.routineName,
    required this.completedSteps,
    required this.totalSteps,
    required this.timestamp,
    required this.type,
  }) : id = 'routine-$routineId-${type.name}-${timestamp.millisecondsSinceEpoch}';

  @override
  String get title => switch (type) {
    TimelineEventType.routineStarted => 'Started: $routineName',
    TimelineEventType.routineCompleted => 'Completed: $routineName',
    _ => routineName,
  };

  @override
  String get description => '$completedSteps of $totalSteps steps completed';
}

// ---------------------------------------------------------------------------
// HabitEvent — habit check-in event
// ---------------------------------------------------------------------------

class HabitEvent implements TimelineEvent {
  @override
  final String id;

  @override
  final DateTime timestamp;

  final String habitId;
  final String habitName;
  final bool completed;
  final int currentStreak;

  @override
  final TimelineEventType type = TimelineEventType.habitChecked;

  HabitEvent({
    required this.habitId,
    required this.habitName,
    required this.completed,
    required this.currentStreak,
    required this.timestamp,
  }) : id = 'habit-$habitId-${timestamp.millisecondsSinceEpoch}';

  @override
  String get title => completed
      ? 'Checked in: $habitName'
      : 'Missed: $habitName';

  @override
  String get description =>
      completed ? 'Streak: $currentStreak days' : 'Streak reset to 0';
}

// ---------------------------------------------------------------------------
// MoodEvent — mood logging event
// ---------------------------------------------------------------------------

class MoodEvent implements TimelineEvent {
  @override
  final String id;

  @override
  final DateTime timestamp;

  final String moodId;
  final String mood; // e.g., "excited", "anxious", "calm"
  final String? notes;
  final int? energyLevel; // 1–5 scale if captured

  @override
  final TimelineEventType type = TimelineEventType.moodLogged;

  MoodEvent({
    required this.moodId,
    required this.mood,
    this.notes,
    this.energyLevel,
    required this.timestamp,
  }) : id = 'mood-$moodId-${timestamp.millisecondsSinceEpoch}';

  @override
  String get title => 'Mood: $mood';

  @override
  String get description {
    final parts = <String>[];
    if (energyLevel != null) parts.add('Energy: $energyLevel/5');
    if (notes != null && notes!.isNotEmpty) {
      parts.add('Note: ${notes!.substring(0, 50)}${notes!.length > 50 ? '...' : ''}');
    }
    return parts.isNotEmpty ? parts.join(' • ') : '—';
  }
}
