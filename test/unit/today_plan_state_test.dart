import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/day_plan.dart';
import 'package:neuroflow/executive/day_resolver.dart';
import 'package:neuroflow/executive/today_plan_projection.dart';
import 'package:neuroflow/executive/today_plan_state.dart';

DayPlan _base() => const DayPlan(blocks: [
      PlanBlock(
        id: 'commute',
        title: 'Commute',
        startMinutes: 340,
        endMinutes: 360,
        kind: PlanBlockKind.commute,
        isLocked: true,
        decision: ProposalDecision.notApplicable,
      ),
      PlanBlock(
        id: 'shift',
        title: 'Gas Compliance Shift',
        startMinutes: 360,
        endMinutes: 870,
        kind: PlanBlockKind.anchor,
        isLocked: true,
        decision: ProposalDecision.notApplicable,
      ),
    ]);

DayPlan _proposal() => DayPlan(blocks: [
      ..._base().blocks,
      const PlanBlock(
        id: 'recovery',
        title: 'Recovery Buffer',
        startMinutes: 890,
        endMinutes: 930,
        kind: PlanBlockKind.recoveryBuffer,
      ),
      const PlanBlock(
        id: 'gym',
        title: 'Gym',
        startMinutes: 930,
        endMinutes: 1000,
        kind: PlanBlockKind.flex,
      ),
      const PlanBlock(
        id: 'open',
        title: 'Open Space',
        startMinutes: 1000,
        endMinutes: 1080,
        kind: PlanBlockKind.openSpace,
        decision: ProposalDecision.notApplicable,
      ),
    ]);

void main() {
  group('TodayPlanController contract',
      () {
    late TodayPlanController controller;

    setUp(() {
      controller = TodayPlanController();
      controller.loadProposal(base: _base(), proposal: _proposal());
    });

    test('loadProposal starts undecided with pending selectable blocks',
        () {
      final s = controller.state;
      expect(s.outcome, ProposalOutcome.undecided);
      expect(s.isReviewing, isFalse);
      expect(s.phase, TodayPlanPhase.proposalReady);
      expect(s.decisions['gym'], ProposalDecision.pending);
      expect(s.decisions['recovery'], ProposalDecision.pending);
      expect(s.decisions.containsKey('shift'), isFalse);
    });

    test('Accept Day accepts all selectable and sets accepted',
        () {
      controller.acceptDay();
      final s = controller.state;
      expect(s.outcome, ProposalOutcome.accepted);
      expect(s.phase, TodayPlanPhase.accepted);
      expect(s.decisions['gym'], ProposalDecision.accepted);
      expect(s.decisions['recovery'], ProposalDecision.accepted);
      expect(s.undoSnapshot, isNotNull);
    });

    test('Review → toggle → Done with some accepted → partial + drops others',
        () {
      controller.startReview();
      expect(controller.state.phase, TodayPlanPhase.reviewing);

      controller.toggleBlock('gym');
      expect(controller.state.decisions['gym'], ProposalDecision.accepted);

      controller.finishReview();
      final s = controller.state;
      expect(s.outcome, ProposalOutcome.partiallyAccepted);
      expect(s.phase, TodayPlanPhase.partiallyAccepted);
      expect(s.sessionPlan!.blocks.any((b) => b.id == 'gym'), isTrue);
      expect(s.sessionPlan!.blocks.any((b) => b.id == 'recovery'), isFalse);
      // Locked anchors remain
      expect(s.sessionPlan!.blocks.any((b) => b.id == 'shift'), isTrue);
    });

    test('Done Reviewing with zero selections rejects and restores base',
        () {
      controller.startReview();
      controller.finishReview();
      final s = controller.state;
      expect(s.outcome, ProposalOutcome.rejected);
      expect(s.phase, TodayPlanPhase.rejected);
      expect(s.sessionPlan, _base());
    });

    test('Keep Original restores base and marks rejected', () {
      controller.keepOriginal();
      final s = controller.state;
      expect(s.outcome, ProposalOutcome.rejected);
      expect(s.sessionPlan, _base());
      expect(s.undoSnapshot, isNotNull);
    });

    test('Not Now restores base and goes ambient (dismissed)', () {
      controller.notNow();
      final s = controller.state;
      expect(s.outcome, ProposalOutcome.dismissed);
      expect(s.phase, TodayPlanPhase.ambient);
      expect(s.sessionPlan, _base());
    });

    test('Undo restores prior axes after Accept Day', () {
      controller.acceptDay();
      expect(controller.state.outcome, ProposalOutcome.accepted);
      controller.undo();
      final s = controller.state;
      expect(s.outcome, ProposalOutcome.undecided);
      expect(s.phase, TodayPlanPhase.proposalReady);
      expect(s.undoSnapshot, isNull);
    });

    test('needsAttention maps to requiresAttention phase', () {
      controller.loadProposal(
        base: _base(),
        proposal: _proposal(),
        needsAttention: true,
      );
      expect(controller.state.phase, TodayPlanPhase.requiresAttention);
    });

    test('Keep Day Open from unavailable clears error, no undo',
        () {
      controller.setUnavailable(const InvalidScheduleRule(
        ruleId: 'r1',
        field: 'byDay',
        value: {},
        reason: 'empty',
      ));
      expect(controller.state.phase, TodayPlanPhase.unavailable);
      controller.keepDayOpen();
      expect(controller.state.phase, TodayPlanPhase.ambient);
      expect(controller.state.undoSnapshot, isNull);
    });

    test('locked and openSpace blocks are never selectable', () {
      controller.startReview();
      controller.toggleBlock('shift'); // locked
      controller.toggleBlock('open'); // notApplicable
      expect(controller.state.decisions.containsKey('shift'), isFalse);
      expect(controller.state.decisions.containsKey('open'), isFalse);
    });
  });

  group('TodayPlanProjection', () {
    const projection = TodayPlanProjection();

    test('proposalReady shows accept/review actions', () {
      final c = TodayPlanController()
        ..loadProposal(base: _base(), proposal: _proposal());
      final view = projection.project(c.state);
      expect(view.showAcceptReviewActions, isTrue);
      expect(view.showDoneReviewing, isFalse);
      expect(view.canUndo, isFalse);
    });

    test('after accept, canUndo is true and actions hide', () {
      final c = TodayPlanController()
        ..loadProposal(base: _base(), proposal: _proposal())
        ..acceptDay();
      final view = projection.project(c.state);
      expect(view.canUndo, isTrue);
      expect(view.showAcceptReviewActions, isFalse);
      expect(view.phase, TodayPlanPhase.accepted);
    });
  });
}
