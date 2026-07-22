// Executive-layer state machine for the Today plan proposal flow.
// Pure Dart. Mirrors the locked interaction contract in
// docs/today_screen_interaction_contract.md.
// Does not import Flutter or intelligence.

import 'package:neuroflow/domain/day_plan.dart';
import 'package:neuroflow/executive/day_resolver.dart';

/// High-level phase derived for UI (projection), not the storage model.
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

/// Snapshot used by Undo — carries the three axes the contract requires.
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

/// Production state for the schedule-proposal session.
///
/// Distinct from the older task-centric [TodayState] in providers.dart.
class TodayPlanState {
  final DayPlan? basePlan;
  final DayPlan? latestProposal;
  final DayPlan? sessionPlan;
  final Map<String, ProposalDecision> decisions;
  final ProposalOutcome outcome;
  final bool needsAttention;
  final bool isReviewing;
  final TodayPlanSnapshot? undoSnapshot;
  final InvalidScheduleRule? error;
  final bool isLoading;

  const TodayPlanState({
    this.basePlan,
    this.latestProposal,
    this.sessionPlan,
    this.decisions = const {},
    this.outcome = ProposalOutcome.undecided,
    this.needsAttention = false,
    this.isReviewing = false,
    this.undoSnapshot,
    this.error,
    this.isLoading = false,
  });

  /// Invariant: isReviewing may only be true when outcome is undecided.
  bool get isValid =>
      !isReviewing || outcome == ProposalOutcome.undecided;

  TodayPlanPhase get phase {
    if (isLoading) return TodayPlanPhase.loading;
    if (error != null) return TodayPlanPhase.unavailable;
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
        if (needsAttention) return TodayPlanPhase.requiresAttention;
        if (sessionPlan == null && basePlan == null) {
          return TodayPlanPhase.ambient;
        }
        return TodayPlanPhase.proposalReady;
    }
  }

  TodayPlanState copyWith({
    DayPlan? basePlan,
    DayPlan? latestProposal,
    DayPlan? sessionPlan,
    Map<String, ProposalDecision>? decisions,
    ProposalOutcome? outcome,
    bool? needsAttention,
    bool? isReviewing,
    TodayPlanSnapshot? undoSnapshot,
    InvalidScheduleRule? error,
    bool? isLoading,
    bool clearUndo = false,
    bool clearError = false,
  }) {
    return TodayPlanState(
      basePlan: basePlan ?? this.basePlan,
      latestProposal: latestProposal ?? this.latestProposal,
      sessionPlan: sessionPlan ?? this.sessionPlan,
      decisions: decisions ?? this.decisions,
      outcome: outcome ?? this.outcome,
      needsAttention: needsAttention ?? this.needsAttention,
      isReviewing: isReviewing ?? this.isReviewing,
      undoSnapshot: clearUndo ? null : (undoSnapshot ?? this.undoSnapshot),
      error: clearError ? null : (error ?? this.error),
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// Deterministic controller implementing the locked interaction contract.
class TodayPlanController {
  TodayPlanState _state;

  TodayPlanController([TodayPlanState? initial])
      : _state = initial ?? const TodayPlanState(isLoading: true);

  TodayPlanState get state => _state;

  TodayPlanSnapshot _capture() {
    return TodayPlanSnapshot(
      sessionPlan: _state.sessionPlan ?? const DayPlan(blocks: []),
      decisions: Map.unmodifiable(_state.decisions),
      outcome: _state.outcome,
      needsAttention: _state.needsAttention,
      isReviewing: _state.isReviewing,
    );
  }

  /// Seed a ready proposal from resolver output + optional flex proposals.
  void loadProposal({
    required DayPlan base,
    required DayPlan proposal,
    bool needsAttention = false,
  }) {
    final decisions = <String, ProposalDecision>{
      for (final b in proposal.blocks)
        if (b.isSelectable) b.id: ProposalDecision.pending,
    };
    _state = TodayPlanState(
      basePlan: base,
      latestProposal: proposal,
      sessionPlan: proposal,
      decisions: decisions,
      outcome: ProposalOutcome.undecided,
      needsAttention: needsAttention,
      isReviewing: false,
      isLoading: false,
    );
  }

  void setUnavailable(InvalidScheduleRule error) {
    _state = TodayPlanState(error: error, isLoading: false);
  }

  void setLoading() {
    _state = const TodayPlanState(isLoading: true);
  }

  /// Accept Day — accept all selectable blocks.
  void acceptDay() {
    if (_state.outcome != ProposalOutcome.undecided || _state.isReviewing) {
      return;
    }
    final snap = _capture();
    final next = Map<String, ProposalDecision>.from(_state.decisions);
    for (final key in next.keys) {
      next[key] = ProposalDecision.accepted;
    }
    final plan = _state.sessionPlan!;
    _state = _state.copyWith(
      sessionPlan: plan.withDecisions(next),
      decisions: next,
      outcome: ProposalOutcome.accepted,
      needsAttention: false,
      isReviewing: false,
      undoSnapshot: snap,
    );
  }

  /// Enter granular review mode.
  void startReview() {
    if (_state.outcome != ProposalOutcome.undecided) return;
    _state = _state.copyWith(isReviewing: true);
  }

  /// Toggle a selectable block during review.
  void toggleBlock(String id) {
    if (!_state.isReviewing) return;
    final plan = _state.sessionPlan;
    if (plan == null) return;
    final block = plan.blocks.where((b) => b.id == id).firstOrNull;
    if (block == null || !block.isSelectable) return;

    final next = Map<String, ProposalDecision>.from(_state.decisions);
    final current = next[id] ?? ProposalDecision.pending;
    next[id] = current == ProposalDecision.accepted
        ? ProposalDecision.pending
        : ProposalDecision.accepted;

    _state = _state.copyWith(
      decisions: next,
      sessionPlan: plan.withDecisions(next),
    );
  }

  /// Done Reviewing.
  ///
  /// - 0 accepted → reject + restore base
  /// - some accepted → partial, drop unselected selectable blocks
  /// - all accepted → full accept
  void finishReview() {
    if (!_state.isReviewing) return;
    final snap = _capture();
    final plan = _state.sessionPlan!;
    final selectable =
        plan.blocks.where((b) => b.isSelectable).toList(growable: false);
    final acceptedCount = selectable
        .where((b) =>
            (_state.decisions[b.id] ?? b.decision) == ProposalDecision.accepted)
        .length;

    if (acceptedCount == 0) {
      _state = TodayPlanState(
        basePlan: _state.basePlan,
        latestProposal: _state.latestProposal,
        sessionPlan: _state.basePlan,
        decisions: const {},
        outcome: ProposalOutcome.rejected,
        needsAttention: false,
        isReviewing: false,
        undoSnapshot: snap,
      );
      return;
    }

    final kept = plan.keptAfterAccept(_state.decisions);
    final outcome = acceptedCount == selectable.length
        ? ProposalOutcome.accepted
        : ProposalOutcome.partiallyAccepted;

    _state = _state.copyWith(
      sessionPlan: kept,
      outcome: outcome,
      needsAttention: false,
      isReviewing: false,
      undoSnapshot: snap,
    );
  }

  /// Keep Original — restore base, mark rejected.
  void keepOriginal() {
    if (_state.outcome != ProposalOutcome.undecided) return;
    final snap = _capture();
    _state = TodayPlanState(
      basePlan: _state.basePlan,
      latestProposal: _state.latestProposal,
      sessionPlan: _state.basePlan,
      decisions: const {},
      outcome: ProposalOutcome.rejected,
      needsAttention: false,
      isReviewing: false,
      undoSnapshot: snap,
    );
  }

  /// Not Now — restore base, ambient (dismissed).
  void notNow() {
    if (_state.outcome != ProposalOutcome.undecided) return;
    final snap = _capture();
    _state = TodayPlanState(
      basePlan: _state.basePlan,
      latestProposal: _state.latestProposal,
      sessionPlan: _state.basePlan,
      decisions: const {},
      outcome: ProposalOutcome.dismissed,
      needsAttention: false,
      isReviewing: false,
      undoSnapshot: snap,
    );
  }

  /// Undo last user action.
  void undo() {
    final snap = _state.undoSnapshot;
    if (snap == null) return;
    _state = TodayPlanState(
      basePlan: _state.basePlan,
      latestProposal: _state.latestProposal,
      sessionPlan: snap.sessionPlan,
      decisions: Map.from(snap.decisions),
      outcome: snap.outcome,
      needsAttention: snap.needsAttention,
      isReviewing: snap.isReviewing,
      undoSnapshot: null,
    );
  }

  /// Keep Day Open — only from unavailable. No undo point.
  void keepDayOpen() {
    if (_state.error == null) return;
    _state = TodayPlanState(
      basePlan: _state.basePlan,
      sessionPlan: _state.basePlan,
      outcome: ProposalOutcome.dismissed,
      isLoading: false,
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
