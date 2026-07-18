// lib/domain/task.dart
//
// Pure domain model — no Flutter, no Drift, no Riverpod.
// Everything above this layer depends on Task; nothing here depends on anything.

import 'package:uuid/uuid.dart';

import 'package:neuroflow/domain/reentry_note.dart';

enum EnergyLevel { low, medium, high }

enum TaskStatus { pending, inProgress, completed, skipped, paused, blocked }

class Task {
  final String id;
  final String title;
  final String? notes;
  final EnergyLevel energy;
  final TaskStatus status;
  final DateTime createdAt;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final DateTime? activeStartedAt;
  final int? estimatedMinutes;
  final ReentryNote? reentryNote;
  final bool isQuickWin; // §QW — eligible for auto-mode Quick Wins list

  const Task({
    required this.id,
    required this.title,
    this.notes,
    required this.energy,
    this.status = TaskStatus.pending,
    required this.createdAt,
    this.dueDate,
    this.completedAt,
    this.activeStartedAt,
    this.estimatedMinutes,
    this.reentryNote,
    this.isQuickWin = false,
  });

  factory Task.create({
    required String title,
    String? notes,
    EnergyLevel energy = EnergyLevel.medium,
    DateTime? dueDate,
    DateTime? completedAt,
    DateTime? activeStartedAt,
    int? estimatedMinutes,
    ReentryNote? reentryNote,
    bool isQuickWin = false,
  }) {
    return Task(
      id: const Uuid().v4(),
      title: title,
      notes: notes,
      energy: energy,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      dueDate: dueDate,
      completedAt: completedAt,
      activeStartedAt: activeStartedAt,
      estimatedMinutes: estimatedMinutes,
      reentryNote: reentryNote,
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
    DateTime? activeStartedAt,
    int? estimatedMinutes,
    ReentryNote? reentryNote,
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
      activeStartedAt: activeStartedAt ?? this.activeStartedAt,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      reentryNote: reentryNote ?? this.reentryNote,
      isQuickWin: isQuickWin ?? this.isQuickWin,
    );
  }

  bool get isPending => status == TaskStatus.pending;
  bool get isCompleted => status == TaskStatus.completed;
}
