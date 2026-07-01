// lib/executive/planner.dart
//
// EXECUTIVE LAYER. Imports DOMAIN ONLY. It must NOT import lib/intelligence/.
//
// The invariant (spec §3): Executive never depends on Intelligence being
// available. It runs a complete DeterministicPlanner. Intelligence (Lexi
// on-device / optional cloud) implements the `PlanAdvisor` seam below and is
// injected as an OPTIONAL enhancer — if it's null, cold, slow, or offline, the
// Executive has already produced a full answer. AI is decoration on a complete
// engine, never a dependency.

import '../domain/task.dart';

/// Everything the planner needs to decide, captured deterministically.
class ContextSnapshot {
  final DateTime now;
  final int? todayMood; // 1..5, null = not logged
  final DateTime? lastInteraction; // for inferred low-engagement
  final int inferredQuietHour; // default 11 — past this with tasks pending = lighter-day signal (§10)

  const ContextSnapshot({
    required this.now,
    this.todayMood,
    this.lastInteraction,
    this.inferredQuietHour = 11,
  });
}

class NextBestAction {
  final Task? task; // null = nothing to surface (a calm, valid state)
  final String reason; // short, for the UI's one-line "why this"
  const NextBestAction(this.task, this.reason);
}

/// Optional Intelligence seam. Implemented in lib/intelligence/ (Lexi). The
/// Executive depends on THIS interface, defined here in its own layer — not on
/// the Intelligence module.
///
/// Null-object pattern (post-review change, replaces nullable-PlanAdvisor):
/// callers always hold a non-null PlanAdvisor — DEFAULT to [NoOpPlanAdvisor]
/// rather than null + scattered null-checks. This makes "Intelligence absent"
/// a normal, type-safe code path instead of a special case every call site has
/// to remember to guard. The Riverpod provider for PlanAdvisor defaults to
/// NoOpPlanAdvisor and is overridden once the Lexi bridge (§14) is wired.
abstract class PlanAdvisor {
  /// May reorder/annotate, but must degrade safely; returning the input
  /// unchanged is always a valid implementation. Never required to do work.
  Future<List<Task>> refine(List<Task> deterministicOrder, ContextSnapshot ctx);
}

/// The default PlanAdvisor. Identity function — hands back the deterministic
/// order untouched. This is what the app runs on until the on-device Lexi
/// bridge (§14, top build risk) lands, and what it falls back to instantly if
/// that bridge is cold, slow, or the device has no on-device model support.
class NoOpPlanAdvisor implements PlanAdvisor {
  const NoOpPlanAdvisor();

  @override
  Future<List<Task>> refine(List<Task> deterministicOrder, ContextSnapshot ctx) async {
    return deterministicOrder;
  }
}

abstract class Planner {
  bool shouldEnterQuickWins(ContextSnapshot ctx);

  /// The deterministic candidate list, in priority order, for whichever mode
  /// applies (Quick Wins capped list, or the normal actionable order). This is
  /// what gets handed to PlanAdvisor.refine() at the orchestration layer —
  /// Planner itself never calls Intelligence.
  List<Task> orderedCandidates(List<Task> open, ContextSnapshot ctx);

  List<Task> quickWins(List<Task> open);
  NextBestAction nextAction(List<Task> open, ContextSnapshot ctx);
}

/// Complete, AI-free engine. This is what ships first and what runs whenever
/// Intelligence is unavailable.
class DeterministicPlanner implements Planner {
  /// Spec §6 cap.
  static const int quickWinCap = 3;

  @override
  bool shouldEnterQuickWins(ContextSnapshot ctx) {
    // Trigger 1 — explicit rough mood check-in (§6).
    if (ctx.todayMood != null && ctx.todayMood! <= 2) return true;

    // Trigger 2 — inferred low-engagement, kept conservative (§10):
    // past the quiet hour, with no interaction yet today.
    final pastQuietHour = ctx.now.hour >= ctx.inferredQuietHour;
    final noInteractionToday = ctx.lastInteraction == null ||
        !_sameDay(ctx.lastInteraction!, ctx.now);
    return pastQuietHour && noInteractionToday;
  }

  @override
  List<Task> quickWins(List<Task> open) {
    final candidates = open
        .where((t) =>
            t.isOpen &&
            t.energy == EnergyTag.lowEnergy &&
            t.priority == Priority.normal)
        .toList();

    // Lowest estimated effort first; unknown effort sorts as "medium" (§6).
    candidates.sort((a, b) =>
        _effort(a).compareTo(_effort(b)));

    return candidates.take(quickWinCap).toList();
  }

  @override
  List<Task> orderedCandidates(List<Task> open, ContextSnapshot ctx) {
    if (shouldEnterQuickWins(ctx)) {
      return quickWins(open);
    }
    final actionable = open.where((t) => t.isOpen).toList()..sort(_byUrgency);
    return actionable;
  }

  @override
  NextBestAction nextAction(List<Task> open, ContextSnapshot ctx) {
    final inQuickWins = shouldEnterQuickWins(ctx);
    final ordered = orderedCandidates(open, ctx);

    if (ordered.isEmpty) {
      return NextBestAction(
        null,
        inQuickWins ? "Nothing easy is tracked. Resting counts." : "Today's clear.",
      );
    }
    return NextBestAction(
      ordered.first,
      inQuickWins ? "A small one for a lighter day." : "Top of today.",
    );
  }

  // High priority first, then soonest due, then oldest.
  int _byUrgency(Task a, Task b) {
    if (a.priority != b.priority) {
      return a.priority == Priority.high ? -1 : 1;
    }
    final ad = a.due, bd = b.due;
    if (ad != null && bd != null) return ad.compareTo(bd);
    if (ad != null) return -1;
    if (bd != null) return 1;
    return a.createdAt.compareTo(b.createdAt);
  }

  int _effort(Task t) => t.estimatedMinutes ?? 15; // unknown == medium
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
