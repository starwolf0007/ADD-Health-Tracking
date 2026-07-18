// lib/executive/planner.dart
//
// Executive layer — the "brain" of NeuroFlow.
// Owns mode detection, Quick Wins auto-swap, and plan refinement seam.
//
// Architecture rules enforced here:
//   • Executive never imports Flutter (no BuildContext, no widgets).
//   • TodayController (in providers.dart) is the SOLE call site for
//     PlanAdvisor.refine(). Executive never calls Intelligence directly.
//   • PlanAdvisor interface is always non-null; default is NoOpPlanAdvisor.

import 'package:neuroflow/domain/task.dart';

// ---------------------------------------------------------------------------
// Mode
// ---------------------------------------------------------------------------

enum DayMode {
  normal, // Standard Today view — primary task + context
  quickWins, // Auto-swapped lighter-day mode — ≤3 low-energy tasks
}

// ---------------------------------------------------------------------------
// Plan — what the Executive hands back to TodayController
// ---------------------------------------------------------------------------

class Plan {
  final DayMode mode;
  final Task? primaryTask; // null means nothing pending
  final List<Task> quickWins; // populated only in quickWins mode
  final String reason; // human-readable string for the UI reassurance line

  const Plan({
    required this.mode,
    this.primaryTask,
    this.quickWins = const [],
    required this.reason,
  });
}

// ---------------------------------------------------------------------------
// PlanAdvisor seam (§14 AI tiering)
//
// Phase 1: NoOpPlanAdvisor — deterministic, never AI-dependent.
// Phase 2: LexiPlanAdvisor wraps on-device Gemini Nano / Apple Foundation.
// Phase 3: CloudPlanAdvisor wraps cloud Gemini (explicit user opt-in only).
//
// TodayController holds the active advisor and calls refine() ONCE per cycle.
// ---------------------------------------------------------------------------

abstract class PlanAdvisor {
  /// Optionally refine a deterministic plan with AI insight.
  /// Must never throw — return [plan] unchanged on any error.
  Future<Plan> refine(Plan plan, List<Task> allPending);
}

class NoOpPlanAdvisor implements PlanAdvisor {
  const NoOpPlanAdvisor();

  @override
  Future<Plan> refine(Plan plan, List<Task> allPending) async => plan;
}

// ---------------------------------------------------------------------------
// Executive engine
// ---------------------------------------------------------------------------

class Executive {
  // Thresholds for auto Quick Wins detection.
  static const int _quickWinsMaxCount = 3;
  static const EnergyLevel _quickWinsMaxEnergy = EnergyLevel.low;

  /// Produce a deterministic Plan from the current pending task list.
  /// This is intentionally synchronous and pure — no I/O, no AI.
  Plan evaluate(List<Task> pending) {
    if (pending.isEmpty) {
      return const Plan(
        mode: DayMode.normal,
        primaryTask: null,
        reason: 'All clear — nothing pending.',
      );
    }

    // Auto Quick Wins: if all pending tasks are low-energy AND there are ≤3,
    // swap to Quick Wins mode automatically (spec v1.3 §QW auto-mode).
    final allLowEnergy = pending.every((t) => t.energy == _quickWinsMaxEnergy);
    if (allLowEnergy && pending.length <= _quickWinsMaxCount) {
      return Plan(
        mode: DayMode.quickWins,
        quickWins: pending,
        reason: 'Lighter load today — showing your easiest wins first.',
      );
    }

    // Normal mode: surface the lowest-energy pending task first.
    final sorted = List<Task>.from(pending)
      ..sort((a, b) => a.energy.index.compareTo(b.energy.index));

    return Plan(
      mode: DayMode.normal,
      primaryTask: sorted.first,
      reason: '',
    );
  }
}
