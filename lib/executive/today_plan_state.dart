// Sealed production state for the Today plan proposal flow.
// Pure Dart. Axes live only on Ready. No public copyWith.
// Mirrors docs/today_screen_interaction_contract.md and docs/today_state_proposal.dart.

import 'package:neuroflow/domain/day_plan.dart';
import 'package:neuroflow/executive/day_resolver.dart';

/// Derived UI phase — never stored as a flat enum on the model.
enum TodayPlanPhase {
  loading,
  proposalReady,
  requiresAttention,
  reviewing,
  partiallyAccepted,
  accepted,
  rejected,
  ambient,
  unavailable,
}

/// Undo snapshot — all three Ready axes, never base/latest proposal.
class TodayPlanSnapshot {
  final DayPlan sessionPlan;
  final Map<String, ProposalDecision> decisions;
  final ProposalOutcome outcome;
  final bool needsAttention;
  final bool isReviewing;

  const TodayPlanSnapshot({
    required this.sessionPlan,
    required this.decisions,
    required this.outcome,
    required this.needsAttention,
    required this.isReviewing,
  });
}

/// Sealed hierarchy — illegal combinations are unrepresentable.
sealed class TodayPlanState {
  const TodayPlanState();
  TodayPlanPhase get phase;
}

final class TodayPlanLoading extends TodayPlanState {
  const TodayPlanLoading();

  @override
  TodayPlanPhase get phase => TodayPlanPhase.loading;
}

final class TodayPlanUnavailable extends TodayPlanState {
  final InvalidScheduleRule error;
  final DayPlan? basePlan;

  const TodayPlanUnavailable({
    required this.error,
    this.basePlan,
  });

  @override
  TodayPlanPhase get phase => TodayPlanPhase.unavailable;
}

/// Only Ready carries outcome / needsAttention / isReviewing.
final class TodayPlanReady extends TodayPlanState {
  final DayPlan basePlan;
  final DayPlan latestProposal;
  final DayPlan sessionPlan;
  final Map<String, ProposalDecision> decisions;
  final ProposalOutcome outcome;
  final bool needsAttention;
  final bool isReviewing;
  final TodayPlanSnapshot? undoSnapshot;

  const TodayPlanReady({
    required this.basePlan,
    required this.latestProposal,
    required this.sessionPlan,
    required this.decisions,
    required this.outcome,
    required this.needsAttention,
    required this.isReviewing,
    this.undoSnapshot,
  }) : assert(!isReviewing || outcome == ProposalOutcome.undecided,
            'isReviewing may only be true when outcome is undecided');

  @override
  TodayPlanPhase get phase {
    if (isReviewing) return TodayPlanPhase.reviewing;
    switch (outcome) {
      case ProposalOutcome.accepted:
        return TodayPlanPhase.accepted;
      case ProposalOutcome.partiallyAccepted:
        return TodayPlanPhase.partiallyAccepted;
      case ProposalOutcome.rejected:
        return TodayPlanPhase.rejected;
      case ProposalOutcome.dismissed:
        return TodayPlanPhase.ambient;
      case ProposalOutcome.undecided:
        return needsAttention
            ? TodayPlanPhase.requiresAttention
            : TodayPlanPhase.proposalReady;
    }
  }

  /// Internal only — not part of the public controller surface.
  TodayPlanReady _copy({
    DayPlan? basePlan,
    DayPlan? latestProposal,
    DayPlan? sessionPlan,
    Map<String, ProposalDecision>? decisions,
    ProposalOutcome? outcome,
    bool? needsAttention,
    bool? isReviewing,
    TodayPlanSnapshot? undoSnapshot,
    bool clearUndo = false,
  }) {
    return TodayPlanReady(
      basePlan: basePlan ?? this.basePlan,
      latestProposal: latestProposal ?? this.latestProposal,
      sessionPlan: sessionPlan ?? this.sessionPlan,
      decisions: decisions ?? this.decisions,
      outcome: outcome ?? this.outcome,
      needsAttention: needsAttention ?? this.needsAttention,
      isReviewing: isReviewing ?? this.isReviewing,
      undoSnapshot: clearUndo ? null : (undoSnapshot ?? this.undoSnapshot),
    );
  }

  TodayPlanSnapshot capture() => TodayPlanSnapshot(
        sessionPlan: sessionPlan,
        decisions: Map.unmodifiable(decisions),
        outcome: outcome,
        needsAttention: needsAttention,
        isReviewing: isReviewing,
      );
}

// ---------------------------------------------------------------------------
// Pure transition helpers (used by the Riverpod Notifier)
// Every helper is a safe no-op when the state is not Ready / not applicable.
// ---------------------------------------------------------------------------

TodayPlanState transitionAcceptDay(TodayPlanState state) {
  if (state is! TodayPlanReady) return state;
  if (state.outcome != ProposalOutcome.undecided || state.isReviewing) {
    return state;
  }
  final next = <String, ProposalDecision>{
    for (final e in state.decisions.entries) e.key: ProposalDecision.accepted,
  };
  return state._copy(
    sessionPlan: state.sessionPlan.withDecisions(next),
    decisions: next,
    outcome: ProposalOutcome.accepted,
    needsAttention: false,
    isReviewing: false,
    undoSnapshot: state.capture(),
  );
}

TodayPlanState transitionStartReview(TodayPlanState state) {
  if (state is! TodayPlanReady) return state;
  if (state.outcome != ProposalOutcome.undecided || state.isReviewing) {
    return state;
  }
  return state._copy(isReviewing: true);
}

TodayPlanState transitionToggleBlock(TodayPlanState state, String id) {
  if (state is! TodayPlanReady) return state;
  if (!state.isReviewing) return state;
  PlanBlock? target;
  for (final b in state.sessionPlan.blocks) {
    if (b.id == id) {
      target = b;
      break;
    }
  }
  if (target == null || !target.isSelectable) return state;

  final next = Map<String, ProposalDecision>.from(state.decisions);
  final current = next[id] ?? ProposalDecision.pending;
  next[id] = current == ProposalDecision.accepted
      ? ProposalDecision.pending
      : ProposalDecision.accepted;

  return state._copy(
    decisions: next,
    sessionPlan: state.sessionPlan.withDecisions(next),
  );
}

TodayPlanState transitionFinishReview(TodayPlanState state) {
  if (state is! TodayPlanReady) return state;
  if (!state.isReviewing) return state;

  final snap = state.capture();
  final selectable = [
    for (final b in state.sessionPlan.blocks)
      if (b.isSelectable) b,
  ];
  final acceptedCount = selectable
      .where((b) =>
          (state.decisions[b.id] ?? b.decision) == ProposalDecision.accepted)
      .length;

  if (acceptedCount == 0) {
    return TodayPlanReady(
      basePlan: state.basePlan,
      latestProposal: state.latestProposal,
      sessionPlan: state.basePlan,
      decisions: const {},
      outcome: ProposalOutcome.rejected,
      needsAttention: false,
      isReviewing: false,
      undoSnapshot: snap,
    );
  }

  final kept = state.sessionPlan.keptAfterAccept(state.decisions);
  final outcome = acceptedCount == selectable.length
      ? ProposalOutcome.accepted
      : ProposalOutcome.partiallyAccepted;

  return state._copy(
    sessionPlan: kept,
    outcome: outcome,
    needsAttention: false,
    isReviewing: false,
    undoSnapshot: snap,
  );
}

TodayPlanState transitionKeepOriginal(TodayPlanState state) {
  if (state is! TodayPlanReady) return state;
  if (state.outcome != ProposalOutcome.undecided) return state;
  return TodayPlanReady(
    basePlan: state.basePlan,
    latestProposal: state.latestProposal,
    sessionPlan: state.basePlan,
    decisions: const {},
    outcome: ProposalOutcome.rejected,
    needsAttention: false,
    isReviewing: false,
    undoSnapshot: state.capture(),
  );
}

TodayPlanState transitionNotNow(TodayPlanState state) {
  if (state is! TodayPlanReady) return state;
  if (state.outcome != ProposalOutcome.undecided) return state;
  return TodayPlanReady(
    basePlan: state.basePlan,
    latestProposal: state.latestProposal,
    sessionPlan: state.basePlan,
    decisions: const {},
    outcome: ProposalOutcome.dismissed,
    needsAttention: false,
    isReviewing: false,
    undoSnapshot: state.capture(),
  );
}

TodayPlanState transitionUndo(TodayPlanState state) {
  if (state is! TodayPlanReady) return state;
  final snap = state.undoSnapshot;
  if (snap == null) return state;
  return TodayPlanReady(
    basePlan: state.basePlan,
    latestProposal: state.latestProposal,
    sessionPlan: snap.sessionPlan,
    decisions: Map<String, ProposalDecision>.from(snap.decisions),
    outcome: snap.outcome,
    needsAttention: snap.needsAttention,
    isReviewing: snap.isReviewing,
    undoSnapshot: null,
  );
}

TodayPlanState transitionKeepDayOpen(TodayPlanState state) {
  if (state is! TodayPlanUnavailable) return state;
  // Ambient with optional base restored. No undo point.
  final base = state.basePlan;
  if (base == null) {
    return const TodayPlanLoading(); // nothing to show; back to loading
  }
  return TodayPlanReady(
    basePlan: base,
    latestProposal: base,
    sessionPlan: base,
    decisions: const {},
    outcome: ProposalOutcome.dismissed,
    needsAttention: false,
    isReviewing: false,
  );
}

/// Build a Ready state from base + proposal (internal / debug seed only).
TodayPlanReady buildReady({
  required DayPlan base,
  required DayPlan proposal,
  bool needsAttention = false,
}) {
  final decisions = <String, ProposalDecision>{
    for (final b in proposal.blocks)
      if (b.isSelectable) b.id: ProposalDecision.pending,
  };
  return TodayPlanReady(
    basePlan: base,
    latestProposal: proposal,
    sessionPlan: proposal,
    decisions: decisions,
    outcome: ProposalOutcome.undecided,
    needsAttention: needsAttention,
    isReviewing: false,
  );
}
