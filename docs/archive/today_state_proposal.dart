// Proposed production state shape — Claude (Chief Builder), rev 2.
// STATUS: Proposal, not committed. Still needs a look against the real
// repo's existing conventions before it's final.
//
// Rev 2 addresses ChatGPT's review of rev 1:
//
// 1. Rev 1's `isReviewing: bool` dropped decision-outcome tracking
//    entirely (accepted/rejected/partiallyAccepted/ambient had nowhere
//    to live) — that critique was correct. But collapsing all eight
//    tested phases into one flat `TodayReadyPhase` enum recreates the
//    original problem one level down: requiresAttention isn't a
//    different KIND of proposal than proposalReady, it's the same thing
//    plus a flag; reviewing is a UI mode, not a decision outcome. Kept
//    as three separate axes instead — outcome, needsAttention,
//    isReviewing — so each stays exactly what it is.
//
// 2. The undo snapshot now carries all three axes, not just
//    isReviewing, so Undo genuinely restores the full pre-action state
//    per the contract. basePlan/latestProposal aren't in the snapshot —
//    they're external truth (what the resolver says), not something a
//    user action needs to roll back.
//
// 3. Renamed per the naming discussion: proposedPlan → latestProposal,
//    displayedPlan → sessionPlan (this is domain state that decisions
//    get applied to throughout the whole ready lifecycle, not merely
//    what happens to be on screen). Not adopting `committedPlan` as a
//    fourth field — once outcome is accepted, sessionPlan already IS
//    the committed plan. A genuinely separate persisted copy would be a
//    derived-not-stored exception that needs its own justification, and
//    I don't think it clears that bar. If accepting later needs to
//    write something durable, that's task-level intent (per the
//    existing "accept writes intent onto tasks, never a day snapshot"
//    rule) — not a new plan object here.

enum ProposalOutcome { undecided, accepted, partiallyAccepted, rejected, dismissed }

@freezed
sealed class TodayState with _$TodayState {
  const factory TodayState.loading() = TodayLoading;

  const factory TodayState.unavailable({
    required InvalidScheduleRule error,
  }) = TodayUnavailable;

  const factory TodayState.ready({
    required DayPlan basePlan,          // settled plan before this proposal
    required DayPlan latestProposal,    // what the resolver currently says — can change live
    required DayPlan sessionPlan,       // frozen plan this session's decisions apply to
    required Map<String, ProposalDecision> decisions,
    required ProposalOutcome outcome,
    required bool needsAttention,       // flag on an undecided proposal, not a separate outcome
    required bool isReviewing,          // UI mode — invariant: only true when outcome == undecided
    TodayReadySnapshot? undoSnapshot,
  }) = TodayReady;
}

@freezed
class TodayReadySnapshot with _$TodayReadySnapshot {
  const factory TodayReadySnapshot({
    required DayPlan sessionPlan,
    required Map<String, ProposalDecision> decisions,
    required ProposalOutcome outcome,
    required bool needsAttention,
    required bool isReviewing,
  }) = _TodayReadySnapshot;
}

// Open questions for repo review — not resolved here:
//
// - proposalSessionId: ChatGPT raised whether the snapshot needs one, to
//   handle the resolver recomputing latestProposal mid-review. Whether
//   this is a real scenario (does Calendar sync currently trigger a
//   fresh proposal mid-session?) is a live-repo question, not one I can
//   answer blind. If it's real, it's an addition to both TodayReady and
//   the snapshot.
//
// - recoverableError: unclear whether this is a genuinely distinct
//   concept from TodayUnavailable, or whether "retry" just means
//   re-fetching a fresh latestProposal (outcome back to undecided). If
//   it's the latter, it may not need to exist as its own state at all.
//
// - The isReviewing-only-when-outcome-is-undecided invariant isn't
//   enforced by the type itself — Freezed won't stop someone
//   constructing an invalid combination. That's a smaller, more
//   tractable problem than the original flat-enum version (one
//   invariant vs. many), but it's still a controller-level rule to
//   enforce, not something the type system guarantees for free.
