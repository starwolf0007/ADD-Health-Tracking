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
//   • Quick Wins entry is derived from user state, never from the shape of
//     the task list — see DayCapacity below and spec §6.

import 'package:neuroflow/domain/mood.dart';
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
// DayCapacity — the user-state signals Quick Wins entry is derived from (§6)
//
// Spec §6 is explicit that Quick Wins is "entered and exited automatically by
// signal, never by tap", and that the low-energy filter "is just how
// candidates are found". Those are two different jobs:
//
//   entry     ← how the person is doing        (this type)
//   selection ← which tasks the mode shows     (energy + effort, capped)
//
// Collapsing the second into the first inverts the feature: the reduction
// would arrive when the list happens to be light rather than when the person
// is depleted, and could never arrive on a heavy day — precisely when it is
// needed most.
// ---------------------------------------------------------------------------

class DayCapacity {
  /// The most recent mood check-in logged today, or null if none has been.
  ///
  /// Per `domain/mood.dart` this is the real Quick Wins trigger: a check-in at
  /// `low` or below reshapes Today until a better one lands or the day rolls.
  final MoodLevel? latestMood;

  const DayCapacity({this.latestMood});

  /// No signal available. Treated as a normal day — absence of evidence that
  /// the day is rough is not evidence that it is.
  static const DayCapacity unknown = DayCapacity();

  /// Whether the signals indicate a lighter day.
  ///
  /// Additional signals (inferred low engagement, sleep, resting HR) belong
  /// here as they become available — §6 leaves the exact set open. They do not
  /// belong in the task-list inspection below.
  bool get indicatesLighterDay => latestMood?.triggersQuickWins ?? false;
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
  /// §6 locked invariant: the Quick Wins list is capped at three. The cap is
  /// the mechanism — an uncapped low-energy list is still a shame pile.
  static const int _quickWinsMaxCount = 3;

  /// §6: candidates are found by low energy. This selects what the mode shows;
  /// it never decides whether the mode is entered.
  static const EnergyLevel _quickWinCandidateEnergy = EnergyLevel.low;

  /// Produce a deterministic Plan from the current pending task list and the
  /// day's capacity signals.
  ///
  /// Intentionally synchronous and pure — no I/O, no AI. [capacity] defaults
  /// to [DayCapacity.unknown], which yields a normal day.
  Plan evaluate(
    List<Task> pending, {
    DayCapacity capacity = DayCapacity.unknown,
  }) {
    if (pending.isEmpty) {
      return const Plan(
        mode: DayMode.normal,
        primaryTask: null,
        reason: 'All clear — nothing pending.',
      );
    }

    // Entry is a property of the person, not of the list (§6).
    if (capacity.indicatesLighterDay) {
      return Plan(
        mode: DayMode.quickWins,
        quickWins: _quickWinSelection(pending),
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

  /// Which tasks the reshaped Today shows, once entry has already been decided.
  ///
  /// §6: low-energy candidates, lowest estimated effort first, capped at three.
  /// When nothing qualifies on energy the cap still applies to the whole list —
  /// containment is the feature, so a rough day never falls back to a full one.
  List<Task> _quickWinSelection(List<Task> pending) {
    final candidates = pending
        .where((task) => task.energy == _quickWinCandidateEnergy)
        .toList();
    final pool = candidates.isNotEmpty ? candidates : List<Task>.from(pending);
    pool.sort(_byEffortThenEnergy);
    return pool.take(_quickWinsMaxCount).toList();
  }

  /// Lowest estimated effort first (§6: "the point is momentum, not
  /// coverage"). Tasks with no estimate sort last — an unknown estimate is not
  /// evidence of a small one. Ties break on energy, then creation order, so
  /// the selection is stable across evaluations.
  static int _byEffortThenEnergy(Task a, Task b) {
    final aEffort = a.estimatedMinutes;
    final bEffort = b.estimatedMinutes;
    if (aEffort != bEffort) {
      if (aEffort == null) return 1;
      if (bEffort == null) return -1;
      final byEffort = aEffort.compareTo(bEffort);
      if (byEffort != 0) return byEffort;
    }
    final byEnergy = a.energy.index.compareTo(b.energy.index);
    if (byEnergy != 0) return byEnergy;
    return a.createdAt.compareTo(b.createdAt);
  }
}
