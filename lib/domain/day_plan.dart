// Domain types for the Today plan / proposal flow.
// Pure Dart. No Flutter, no Riverpod, no Drift.

/// Decision applied to a selectable block during review / accept.
enum ProposalDecision {
  notApplicable,
  pending,
  accepted,
  rejected,
}

/// Outcome of the current proposal session.
enum ProposalOutcome {
  undecided,
  accepted,
  partiallyAccepted,
  rejected,
  dismissed, // "Not now" path
}

/// Visual / semantic kind of a block in a DayPlan.
enum PlanBlockKind {
  anchor,
  flex,
  runway,
  recoveryBuffer,
  openSpace,
  commute,
}

/// Dev / test scenarios used by gated loadScenario.
enum MockDayScenario {
  normalWorkday,
  overloadedDay,
  lowEnergyDay,
  lateAppointment,
}

/// One timed block inside a [DayPlan].
class PlanBlock {
  final String id;
  final String title;
  final int startMinutes; // minutes from midnight
  final int endMinutes;
  final PlanBlockKind kind;
  final String? explanation;
  final bool isLocked;
  final ProposalDecision decision;

  const PlanBlock({
    required this.id,
    required this.title,
    required this.startMinutes,
    required this.endMinutes,
    required this.kind,
    this.explanation,
    this.isLocked = false,
    this.decision = ProposalDecision.pending,
  });

  bool get isSelectable =>
      !isLocked && decision != ProposalDecision.notApplicable;

  PlanBlock withDecision(ProposalDecision decision) => PlanBlock(
        id: id,
        title: title,
        startMinutes: startMinutes,
        endMinutes: endMinutes,
        kind: kind,
        explanation: explanation,
        isLocked: isLocked,
        decision: decision,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanBlock &&
          id == other.id &&
          title == other.title &&
          startMinutes == other.startMinutes &&
          endMinutes == other.endMinutes &&
          kind == other.kind &&
          explanation == other.explanation &&
          isLocked == other.isLocked &&
          decision == other.decision;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        startMinutes,
        endMinutes,
        kind,
        explanation,
        isLocked,
        decision,
      );
}

/// Ordered collection of plan blocks for a single calendar day.
class DayPlan {
  final List<PlanBlock> blocks;

  const DayPlan({required this.blocks});

  DayPlan withDecisions(Map<String, ProposalDecision> decisions) {
    return DayPlan(
      blocks: [
        for (final b in blocks)
          if (decisions.containsKey(b.id))
            b.withDecision(decisions[b.id]!)
          else
            b,
      ],
    );
  }

  /// Locked/non-selectable blocks + accepted selectable blocks only.
  DayPlan keptAfterAccept(Map<String, ProposalDecision> decisions) {
    return DayPlan(
      blocks: [
        for (final b in blocks)
          if (!b.isSelectable ||
              (decisions[b.id] ?? b.decision) == ProposalDecision.accepted)
            b.withDecision(decisions[b.id] ?? b.decision),
      ],
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DayPlan &&
          blocks.length == other.blocks.length &&
          _listEquals(blocks, other.blocks);

  @override
  int get hashCode => Object.hashAll(blocks);

  static bool _listEquals(List<PlanBlock> a, List<PlanBlock> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
