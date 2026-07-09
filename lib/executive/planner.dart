// lib/executive/planner.dart
//
// Executive layer — the "brain" of NeuroFlow.
// Owns mode detection, Quick Wins auto-swap, and the plan-refinement seam.
//
// Architecture rules enforced here:
//   • Executive never imports Flutter (no BuildContext, no widgets).
//   • TodayController (in providers.dart) is the SOLE call site for
//     PlanAdvisor.refine(). Executive never calls Intelligence directly.
//   • PlanAdvisor interface is always non-null; default is NoOpPlanAdvisor.
//
// v3 change: evaluate() accepts an optional MoodLevel — the REAL Quick Wins
// trigger from spec §6 — and the interrupted (paused/blocked) task list. Both
// are passed IN as data (the Executive still does no I/O), so determinism
// holds: same inputs, same plan, every time.

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

  /// v3 living-state: interrupted tasks the user could *return* to. Surfaced
  /// separately from the primary action so the UI can offer a Re-Entry path
  /// without overriding the next-best-action. Empty when nothing is paused.
  final List<Task> returnable;

  const Plan({
    required this.mode,
    this.primaryTask,
    this.quickWins = const [],
    this.reason = '',
    this.returnable = const [],
  });

  Plan copyWith({
    DayMode? mode,
    Task? primaryTask,
    List<Task>? quickWins,
    String? reason,
    List<Task>? returnable,
  }) {
    return Plan(
      mode: mode ?? this.mode,
      primaryTask: primaryTask ?? this.primaryTask,
      quickWins: quickWins ?? this.quickWins,
      reason: reason ?? this.reason,
      returnable: returnable ?? this.returnable,
    );
  }
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

  /// Produce a deterministic Plan from the current active task list, today's
  /// mood, and any interrupted (paused/blocked) tasks.
  /// This is intentionally synchronous and pure — no I/O, no AI.
  ///
  /// v3 living-state: `interrupted` tasks are threaded into every branch as
  /// the `returnable` list. They never *replace* the next-best-action — the
  /// UI decides whether to offer the Re-Entry path — but they're always
  /// carried so "the moment of return" is one glance away.
  Plan evaluate(
    List<Task> pending, {
    MoodLevel? mood,
    List<Task> interrupted = const [],
  }) {
    if (pending.isEmpty && interrupted.isEmpty) {
      return const Plan(
        mode: DayMode.normal,
        primaryTask: null,
        reason: 'All clear — nothing pending.',
      );
    }

    // If there's nothing new to start but something to return to, the plan
    // IS the return. (Common ADHD reality: no fresh tasks, one thing half-done.)
    if (pending.isEmpty && interrupted.isNotEmpty) {
      return Plan(
        mode: DayMode.normal,
        primaryTask: null,
        returnable: interrupted,
        reason: 'Nothing new — but you left something mid-step. '
            'Pick up where you paused?',
      );
    }

    // §6 PRIMARY TRIGGER — a rough check-in reshapes the day.
    if (mood != null && mood.triggersQuickWins) {
      final gentle = List<Task>.from(pending)..sort(_byEnergyThenStable);
      return Plan(
        mode: DayMode.quickWins,
        quickWins: gentle.take(_quickWinsMaxCount).toList(),
        returnable: interrupted,
        reason: 'Rough patch logged — here are three gentle wins. '
            'Any one of them counts.',
      );
    }

    // Auto Quick Wins: if all active tasks are low-energy AND there are ≤3,
    // swap to Quick Wins mode automatically (spec v1.3 §QW auto-mode).
    final allLowEnergy =
        pending.every((t) => t.energy == _quickWinsMaxEnergy);
    if (allLowEnergy && pending.length <= _quickWinsMaxCount) {
      return Plan(
        mode: DayMode.quickWins,
        quickWins: pending,
        returnable: interrupted,
        reason: 'Lighter load today — showing your easiest wins first.',
      );
    }

    // Normal mode: surface the lowest-energy active task first.
    final sorted = List<Task>.from(pending)..sort(_byEnergyThenStable);

    return Plan(
      mode: DayMode.normal,
      primaryTask: sorted.first,
      returnable: interrupted,
      reason: '',
    );
  }

  /// Energy ascending, with a deterministic tiebreaker (createdAt, then id)
  /// so equal-energy tasks never reorder unpredictably between evaluations.
  static int _byEnergyThenStable(Task a, Task b) {
    final byEnergy = a.energy.index.compareTo(b.energy.index);
    if (byEnergy != 0) return byEnergy;
    final byCreated = a.createdAt.compareTo(b.createdAt);
    if (byCreated != 0) return byCreated;
    return a.id.compareTo(b.id);
  }
}
