// lib/domain/routine.dart
//
// Routine domain models — pure, no Flutter/Drift dependencies.
// A Routine is a named, ordered sequence of RoutineSteps.
// Steps are walked one at a time; completing the last step completes the routine.
//
// Design intent (ADHD-first):
//   • Routines break overwhelming sequences into single visible steps.
//   • The active step is always ONE thing — no list anxiety.
//   • Completion is celebrated briefly, then the next step surfaces.

import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Schedule
// ---------------------------------------------------------------------------

/// When a routine fires. Phase 1: time-of-day anchors only.
/// Phase 2 will add day-of-week filtering.
enum RoutineAnchor {
  morning, // ~6–9 AM
  midday,  // ~11 AM–1 PM
  evening, // ~5–8 PM
  custom,  // user-defined time (stored in scheduleHour/scheduleMinute)
}

// ---------------------------------------------------------------------------
// RoutineStep
// ---------------------------------------------------------------------------

class RoutineStep {
  final String id;
  final String routineId;
  final int position; // 0-indexed order within the routine
  final String title;
  final String? notes;
  final int? durationMinutes; // optional time box
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
  final int? scheduleHour;   // 0–23, used when anchor == custom
  final int? scheduleMinute; // 0–59, used when anchor == custom
  final bool isActive; // user can disable a routine without deleting it
  final List<RoutineStep> steps;
  final DateTime createdAt;

  const Routine({
    required this.id,
    required this.name,
    required this.anchor,
    this.scheduleHour,
    this.scheduleMinute,
    this.isActive = true,
    this.steps = const [],
    required this.createdAt,
  });

  factory Routine.create({
    required String name,
    required RoutineAnchor anchor,
    int? scheduleHour,
    int? scheduleMinute,
    List<RoutineStep> steps = const [],
  }) {
    return Routine(
      id: const Uuid().v4(),
      name: name,
      anchor: anchor,
      scheduleHour: scheduleHour,
      scheduleMinute: scheduleMinute,
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
    List<RoutineStep>? steps,
  }) {
    return Routine(
      id: id,
      name: name ?? this.name,
      anchor: anchor ?? this.anchor,
      scheduleHour: scheduleHour ?? this.scheduleHour,
      scheduleMinute: scheduleMinute ?? this.scheduleMinute,
      isActive: isActive ?? this.isActive,
      steps: steps ?? this.steps,
      createdAt: createdAt,
    );
  }

  // ------------------------------------------------------------------
  // Computed helpers
  // ------------------------------------------------------------------

  /// The currently active step — first incomplete step in order.
  RoutineStep? get activeStep {
    try {
      return steps
          .where((s) => !s.isComplete)
          .reduce((a, b) => a.position < b.position ? a : b);
    } catch (_) {
      return null; // all steps done
    }
  }

  bool get isComplete => steps.isNotEmpty && steps.every((s) => s.isComplete);

  int get completedCount => steps.where((s) => s.isComplete).length;

  double get progressFraction =>
      steps.isEmpty ? 0.0 : completedCount / steps.length;
}
