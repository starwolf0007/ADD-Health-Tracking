// lib/domain/routine.dart
//
// Routine domain models — pure, no Flutter/Drift dependencies.
// A Routine is a named, ordered sequence of RoutineSteps.

import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Schedule
// ---------------------------------------------------------------------------

enum RoutineAnchor {
  morning, // ~6–9 AM
  midday, // ~11 AM–1 PM
  evening, // ~5–8 PM
  custom, // user-defined time
}

// ---------------------------------------------------------------------------
// RoutineStep
// ---------------------------------------------------------------------------

class RoutineStep {
  final String id;
  final String routineId;
  final int position;
  final String title;
  final String? notes;
  final int? durationMinutes;
  bool isComplete;

  RoutineStep({
    required this.id,
    required this.routineId,
    required this.position,
    required this.title,
    this.notes,
    this.durationMinutes,
    this.isComplete = false,
  });

  factory RoutineStep.create({
    required String routineId,
    required int position,
    required String title,
    String? notes,
    int? durationMinutes,
  }) {
    return RoutineStep(
      id: const Uuid().v4(),
      routineId: routineId,
      position: position,
      title: title,
      notes: notes,
      durationMinutes: durationMinutes,
    );
  }

  RoutineStep copyWith({
    String? title,
    String? notes,
    int? durationMinutes,
    int? position,
    bool? isComplete,
  }) {
    return RoutineStep(
      id: id,
      routineId: routineId,
      position: position ?? this.position,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

// ---------------------------------------------------------------------------
// Routine
// ---------------------------------------------------------------------------

class Routine {
  final String id;
  final String name;
  final RoutineAnchor anchor;
  final int? scheduleHour;
  final int? scheduleMinute;
  final bool isActive;

  /// Which weekdays this routine fires — ISO weekday digits (Mon=1 … Sun=7)
  /// as a compact string, e.g. "12345" for weekdays. Null = every day.
  final String? activeDays;
  final List<RoutineStep> steps;
  final DateTime createdAt;

  const Routine({
    required this.id,
    required this.name,
    required this.anchor,
    this.scheduleHour,
    this.scheduleMinute,
    this.isActive = true,
    this.activeDays,
    this.steps = const [],
    required this.createdAt,
  });

  factory Routine.create({
    required String name,
    required RoutineAnchor anchor,
    int? scheduleHour,
    int? scheduleMinute,
    String? activeDays,
    List<RoutineStep> steps = const [],
  }) {
    return Routine(
      id: const Uuid().v4(),
      name: name,
      anchor: anchor,
      scheduleHour: scheduleHour,
      scheduleMinute: scheduleMinute,
      activeDays: activeDays,
      steps: steps,
      createdAt: DateTime.now(),
    );
  }

  Routine copyWith({
    String? name,
    RoutineAnchor? anchor,
    int? scheduleHour,
    int? scheduleMinute,
    bool? isActive,
    String? activeDays,
    List<RoutineStep>? steps,
  }) {
    return Routine(
      id: id,
      name: name ?? this.name,
      anchor: anchor ?? this.anchor,
      scheduleHour: scheduleHour ?? this.scheduleHour,
      scheduleMinute: scheduleMinute ?? this.scheduleMinute,
      isActive: isActive ?? this.isActive,
      activeDays: activeDays ?? this.activeDays,
      steps: steps ?? this.steps,
      createdAt: createdAt,
    );
  }

  bool firesOn(DateTime date) {
    if (activeDays == null || activeDays!.isEmpty) return true;
    return activeDays!.contains(date.weekday.toString());
  }

  RoutineStep? get activeStep {
    RoutineStep? active;
    for (final step in steps) {
      if (!step.isComplete &&
          (active == null || step.position < active.position)) {
        active = step;
      }
    }
    return active;
  }

  bool get isComplete => steps.isNotEmpty && steps.every((s) => s.isComplete);
  int get completedCount => steps.where((s) => s.isComplete).length;
  double get progressFraction =>
      steps.isEmpty ? 0.0 : completedCount / steps.length;
}
