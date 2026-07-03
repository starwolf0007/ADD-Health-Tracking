// lib/executive/planner.dart
//
// The Executive engine (§3). Deterministic, synchronous, pure.
// Owns mode detection, Quick Wins auto-swap, and next-best-action selection.
// NEVER imports AI, Flutter, Drift, or Riverpod. The PlanAdvisor seam is the
// ONLY door intelligence may knock on — and it may refine a plan, never
// produce one.
//
// v2 change: evaluate() accepts an optional MoodLevel — the REAL Quick Wins
// trigger from spec §6. A check-in at `low` or below reshapes Today into
// ≤3 gentle wins. The signal is passed IN (the Executive still does no I/O),
// so determinism holds: same inputs, same plan, every time.

import '../domain/mood.dart';
import '../domain/task.dart';

// ---------------------------------------------------------------------------
// Plan — the Executive's complete output
// ---------------------------------------------------------------------------

enum DayMode { normal, quickWins }

class Plan {
  final DayMode mode;
  final Task? primaryTask;
  final List<Task> quickWins;
  final String reason;

  const Plan({
    required this.mode,
    this.primaryTask,
    this.quickWins = const [],
    this.reason = '',
  });

  Plan copyWith({
    DayMode? mode,
    Task? primaryTask,
    List<Task>? quickWins,
    String? reason,
  }) {
    return Plan(
      mode: mode ?? this.mode,
      primaryTask: primaryTask ?? this.primaryTask,
      quickWins: quickWins ?? this.quickWins,
      reason: reason ?? this.reason,
    );
  }
}

// ---------------------------------------------------------------------------
// PlanAdvisor seam — the ONLY place AI may touch a plan.
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

  /// Produce a deterministic Plan from the current pending task list and
  /// (optionally) today's latest mood check-in.
  /// Intentionally synchronous and pure — no I/O, no AI, no clock reads.
  Plan evaluate(List<Task> pending, {MoodLevel? mood}) {
    if (pending.isEmpty) {
      return const Plan(
        mode: DayMode.normal,
        primaryTask: null,
        reason: 'All clear — nothing pending.',
      );
    }

    // §6 PRIMARY TRIGGER — a rough check-in reshapes the day.
    // Up to three of the gentlest tasks: quick-win flagged first, then by
    // energy ascending. Copy stays kind; the mode does the caring.
    if (mood != null && mood.triggersQuickWins) {
      final gentle = List<Task>.from(pending)
        ..sort((a, b) {
          if (a.isQuickWin != b.isQuickWin) return a.isQuickWin ? -1 : 1;
          return a.energy.index.compareTo(b.energy.index);
        });
      return Plan(
        mode: DayMode.quickWins,
        quickWins: gentle.take(_quickWinsMaxCount).toList(),
        reason: 'Rough patch logged — here are three gentle wins. '
            'Any one of them counts.',
      );
    }

    // Auto Quick Wins: if all pending tasks are low-energy AND there are ≤3,
    // swap to Quick Wins mode automatically (spec §QW auto-mode).
    final allLowEnergy =
        pending.every((t) => t.energy == _quickWinsMaxEnergy);
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
