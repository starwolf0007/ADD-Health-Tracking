// Projection: sealed TodayPlanState → display values + Lexi briefings.
// Pure Dart. No Flutter imports.

import 'package:neuroflow/domain/day_plan.dart';
import 'package:neuroflow/executive/today_plan_state.dart';

class TodayPlanView {
  final TodayPlanPhase phase;
  final List<PlanBlock> visibleBlocks;
  final bool canUndo;
  final bool showAcceptReviewActions;
  final bool showDoneReviewing;
  final bool showKeepDayOpen;
  final String lexiBriefing;

  const TodayPlanView({
    required this.phase,
    required this.visibleBlocks,
    required this.canUndo,
    required this.showAcceptReviewActions,
    required this.showDoneReviewing,
    required this.showKeepDayOpen,
    required this.lexiBriefing,
  });
}

class TodayPlanProjection {
  const TodayPlanProjection();

  TodayPlanView project(TodayPlanState state) {
    final phase = state.phase;
    final blocks = switch (state) {
      TodayPlanReady(:final sessionPlan) => sessionPlan.blocks,
      _ => const <PlanBlock>[],
    };
    final canUndo = state is TodayPlanReady &&
        state.undoSnapshot != null &&
        phase != TodayPlanPhase.reviewing;

    return TodayPlanView(
      phase: phase,
      visibleBlocks: blocks,
      canUndo: canUndo,
      showAcceptReviewActions: phase == TodayPlanPhase.proposalReady ||
          phase == TodayPlanPhase.requiresAttention,
      showDoneReviewing: phase == TodayPlanPhase.reviewing,
      showKeepDayOpen: phase == TodayPlanPhase.unavailable,
      lexiBriefing: statusBriefing(state),
    );
  }

  String statusBriefing(TodayPlanState state) {
    switch (state.phase) {
      case TodayPlanPhase.loading:
        return "I'm organizing the available time.";
      case TodayPlanPhase.proposalReady:
        return 'A plan is ready for your day.';
      case TodayPlanPhase.requiresAttention:
        return 'Something shifted. Review the adjusted plan when you can.';
      case TodayPlanPhase.reviewing:
        return 'Select the individual blocks you want to keep.';
      case TodayPlanPhase.partiallyAccepted:
        return "I've locked in the blocks you selected. The rest of the time remains open.";
      case TodayPlanPhase.accepted:
        return 'Your day plan is set.';
      case TodayPlanPhase.rejected:
        return 'Proposed changes rejected. Your original timeline has been restored.';
      case TodayPlanPhase.ambient:
        return 'Standing by.';
      case TodayPlanPhase.unavailable:
        return 'No viable plan for this scenario.';
    }
  }
}
