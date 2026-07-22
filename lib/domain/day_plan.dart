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

  PlanBlock copyWith({
    String? id,
    String? title,
    int? startMinutes,
    int? endMinutes,
    PlanBlockKind? kind,
    String? explanation,
    bool? isLocked,
    ProposalDecision? decision,
  }) {
    return PlanBlock(
      id: id ?? this.id,
      title: title ?? this.title,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      kind: kind ?? this.kind,
      explanation: explanation ?? this.explanation,
      isLocked: isLocked ?? this.isLocked,
      decision: decision ?? this.decision,
    );
  }

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

  DayPlan copyWith({List<PlanBlock>? blocks}) =>
      DayPlan(blocks: blocks ?? this.blocks);

  DayPlan withDecisions(Map<String, ProposalDecision> decisions) {
    return DayPlan(
      blocks: blocks
          .map(
            (b) => decisions.containsKey(b.id)
                ? b.copyWith(decision: decisions[b.id])
                : b,
          )
          .toList(),
    );
  }

  /// Blocks that remain after a partial/full accept (locked + accepted).
  DayPlan keptAfterAccept(Map<String, ProposalDecision> decisions) {
    return DayPlan(
      blocks: blocks.where((b) {
        if (!b.isSelectable) return true;
        final d = decisions[b.id] ?? b.decision;
        return d == ProposalDecision.accepted;
      }).toList(),
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
