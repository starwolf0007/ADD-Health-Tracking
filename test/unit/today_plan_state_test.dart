import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/today_plan_provider.dart';
import 'package:neuroflow/domain/day_plan.dart';
import 'package:neuroflow/executive/day_resolver.dart';
import 'package:neuroflow/executive/today_plan_projection.dart';
import 'package:neuroflow/executive/today_plan_state.dart';

void main() {
  late ProviderContainer container;
  const projection = TodayPlanProjection();

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  TodayPlanNotifier notifier() =>
      container.read(todayPlanProvider.notifier);

  TodayPlanState state() => container.read(todayPlanProvider);

  TodayPlanReady ready() {
    final s = state();
    expect(s, isA<TodayPlanReady>());
    return s as TodayPlanReady;
  }

  void seedNormal() => notifier().loadScenario(MockDayScenario.normalWorkday);

  group('initialization',
      () {
    test('provider starts in Loading', () {
      expect(state(), isA<TodayPlanLoading>());
      expect(state().phase, TodayPlanPhase.loading);
    });

    test('loadScenario seeds Ready with pending selectable blocks',
        () {
      seedNormal();
      final s = ready();
      expect(s.outcome, ProposalOutcome.undecided);
      expect(s.isReviewing, isFalse);
      expect(s.needsAttention, isFalse);
      expect(s.phase, TodayPlanPhase.proposalReady);
      expect(s.decisions['gym'], ProposalDecision.pending);
      expect(s.decisions['recovery'], ProposalDecision.pending);
      expect(s.decisions.containsKey('shift'), isFalse);
    });
  });

  group('Accept Day',
      () {
    test('accepts all selectable → accepted', () {
      seedNormal();
      notifier().acceptDay();
      final s = ready();
      expect(s.outcome, ProposalOutcome.accepted);
      expect(s.phase, TodayPlanPhase.accepted);
      expect(s.decisions['gym'], ProposalDecision.accepted);
      expect(s.decisions['recovery'], ProposalDecision.accepted);
      expect(s.undoSnapshot, isNotNull);
    });

    test('safe no-op on Loading', () {
      notifier().acceptDay();
      expect(state(), isA<TodayPlanLoading>());
    });
  });

  group('Review flow',
      () {
    test('partial accept drops unselected selectable blocks',
        () {
      seedNormal();
      notifier().startReview();
      expect(ready().phase, TodayPlanPhase.reviewing);
      notifier().toggleBlock('gym');
      expect(ready().decisions['gym'], ProposalDecision.accepted);
      notifier().finishReview();
      final s = ready();
      expect(s.outcome, ProposalOutcome.partiallyAccepted);
      expect(s.sessionPlan.blocks.any((b) => b.id == 'gym'), isTrue);
      expect(s.sessionPlan.blocks.any((b) => b.id == 'recovery'), isFalse);
      expect(s.sessionPlan.blocks.any((b) => b.id == 'shift'), isTrue);
    });

    test('review → all selected → fully accepted', () {
      seedNormal();
      notifier().startReview();
      for (final id in ready().decisions.keys) {
        notifier().toggleBlock(id);
      }
      notifier().finishReview();
      final s = ready();
      expect(s.outcome, ProposalOutcome.accepted);
      expect(s.phase, TodayPlanPhase.accepted);
    });

    test('Done Reviewing with zero selections rejects + restores base',
        () {
      seedNormal();
      final base = ready().basePlan;
      notifier().startReview();
      notifier().finishReview();
      final s = ready();
      expect(s.outcome, ProposalOutcome.rejected);
      expect(s.sessionPlan, base);
    });

    test('partial acceptance → Undo restores review mode and selections',
        () {
      seedNormal();
      notifier().startReview();
      notifier().toggleBlock('gym');
      final beforeFinish = ready();
      expect(beforeFinish.isReviewing, isTrue);
      expect(beforeFinish.decisions['gym'], ProposalDecision.accepted);
      notifier().finishReview();
      expect(ready().outcome, ProposalOutcome.partiallyAccepted);
      notifier().undo();
      final restored = ready();
      expect(restored.isReviewing, isTrue);
      expect(restored.outcome, ProposalOutcome.undecided);
      expect(restored.decisions['gym'], ProposalDecision.accepted);
      expect(restored.decisions['recovery'], ProposalDecision.pending);
    });

    test('locked and openSpace are never selectable', () {
      notifier().loadScenario(MockDayScenario.lowEnergyDay);
      notifier().startReview();
      notifier().toggleBlock('shift');
      notifier().toggleBlock('open');
      final s = ready();
      expect(s.decisions.containsKey('shift'), isFalse);
      expect(s.decisions.containsKey('open'), isFalse);
    });
  });

  group('Keep Original / Not Now',
      () {
    test('Keep Original restores base, rejected', () {
      seedNormal();
      final base = ready().basePlan;
      notifier().keepOriginal();
      final s = ready();
      expect(s.outcome, ProposalOutcome.rejected);
      expect(s.sessionPlan, base);
      expect(s.undoSnapshot, isNotNull);
    });

    test('Not Now restores base, ambient (dismissed)', () {
      seedNormal();
      final base = ready().basePlan;
      notifier().notNow();
      final s = ready();
      expect(s.outcome, ProposalOutcome.dismissed);
      expect(s.phase, TodayPlanPhase.ambient);
      expect(s.sessionPlan, base);
    });
  });

  group('Disruption',
      () {
    test('simulateDisruption sets needsAttention', () {
      seedNormal();
      notifier().simulateDisruption();
      final s = ready();
      expect(s.needsAttention, isTrue);
      expect(s.phase, TodayPlanPhase.requiresAttention);
      expect(s.outcome, ProposalOutcome.undecided);
    });

    test('disruption → Keep Original restores base without attention',
        () {
      seedNormal();
      final base = ready().basePlan;
      notifier().simulateDisruption();
      notifier().keepOriginal();
      final s = ready();
      expect(s.outcome, ProposalOutcome.rejected);
      expect(s.needsAttention, isFalse);
      expect(s.sessionPlan, base);
    });

    test('disruption → Undo restores needsAttention and outcome',
        () {
      seedNormal();
      notifier().simulateDisruption();
      // Accept creates undo of the disrupted ready state
      notifier().acceptDay();
      expect(ready().outcome, ProposalOutcome.accepted);
      notifier().undo();
      final s = ready();
      expect(s.outcome, ProposalOutcome.undecided);
      expect(s.needsAttention, isTrue);
      expect(s.phase, TodayPlanPhase.requiresAttention);
    });
  });

  group('Undo',
      () {
    test('Undo after Accept restores undecided proposalReady', () {
      seedNormal();
      notifier().acceptDay();
      notifier().undo();
      final s = ready();
      expect(s.outcome, ProposalOutcome.undecided);
      expect(s.phase, TodayPlanPhase.proposalReady);
      expect(s.undoSnapshot, isNull);
    });

    test('Undo is safe no-op when no snapshot', () {
      seedNormal();
      notifier().undo();
      expect(ready().phase, TodayPlanPhase.proposalReady);
    });
  });

  group('Unavailable',
      () {
    test('Keep Day Open clears unavailable, no undo', () {
      seedNormal();
      final base = ready().basePlan;
      notifier().debugSetUnavailable(const InvalidScheduleRule(
        ruleId: 'r1',
        field: 'byDay',
        value: {},
        reason: 'empty',
      ));
      expect(state().phase, TodayPlanPhase.unavailable);
      notifier().keepDayOpen();
      final s = ready();
      expect(s.phase, TodayPlanPhase.ambient);
      expect(s.sessionPlan, base);
      expect(s.undoSnapshot, isNull);
    });

    test('acceptDay is safe no-op on Unavailable', () {
      notifier().debugSetUnavailable(const InvalidScheduleRule(
        ruleId: 'r1',
        field: 'x',
        value: 0,
        reason: 'test',
      ));
      notifier().acceptDay();
      expect(state(), isA<TodayPlanUnavailable>());
    });
  });

  group('Block boundaries',
      () {
    test('exact start and end minutes are preserved on load',
        () {
      seedNormal();
      final gym = ready().sessionPlan.blocks.firstWhere((b) => b.id == 'gym');
      expect(gym.startMinutes, 930);
      expect(gym.endMinutes, 1000);
      final commute =
          ready().sessionPlan.blocks.firstWhere((b) => b.id == 'commute');
      expect(commute.startMinutes, 340);
      expect(commute.endMinutes, 360);
    });
  });

  group('Safe no-ops on invalid context',
      () {
    test('startReview / finishReview / toggle on Loading do nothing',
        () {
      notifier().startReview();
      notifier().toggleBlock('gym');
      notifier().finishReview();
      notifier().keepOriginal();
      notifier().notNow();
      expect(state(), isA<TodayPlanLoading>());
    });
  });

  group('Lexi projection for each phase',
      () {
    test('Loading briefing', () {
      final view = projection.project(state());
      expect(view.lexiBriefing, contains('organizing'));
      expect(view.phase, TodayPlanPhase.loading);
    });

    test('proposalReady briefing + actions', () {
      seedNormal();
      final view = projection.project(state());
      expect(view.phase, TodayPlanPhase.proposalReady);
      expect(view.showAcceptReviewActions, isTrue);
      expect(view.showDoneReviewing, isFalse);
      expect(view.lexiBriefing, contains('plan is ready'));
    });

    test('requiresAttention briefing', () {
      seedNormal();
      notifier().simulateDisruption();
      final view = projection.project(state());
      expect(view.phase, TodayPlanPhase.requiresAttention);
      expect(view.showAcceptReviewActions, isTrue);
      expect(view.lexiBriefing, contains('shifted'));
    });

    test('reviewing briefing', () {
      seedNormal();
      notifier().startReview();
      final view = projection.project(state());
      expect(view.phase, TodayPlanPhase.reviewing);
      expect(view.showDoneReviewing, isTrue);
      expect(view.canUndo, isFalse);
      expect(view.lexiBriefing, contains('Select the individual'));
    });

    test('accepted / partiallyAccepted / rejected / ambient briefings',
        () {
      seedNormal();
      notifier().acceptDay();
      expect(projection.project(state()).lexiBriefing, contains('day plan is set'));

      seedNormal();
      notifier().startReview();
      notifier().toggleBlock('gym');
      notifier().finishReview();
      expect(projection.project(state()).lexiBriefing, contains('locked in'));

      seedNormal();
      notifier().keepOriginal();
      expect(projection.project(state()).lexiBriefing, contains('rejected'));

      seedNormal();
      notifier().notNow();
      expect(projection.project(state()).lexiBriefing, contains('Standing by'));
    });

    test('unavailable briefing + Keep Day Open action', () {
      notifier().debugSetUnavailable(const InvalidScheduleRule(
        ruleId: 'r',
        field: 'f',
        value: 1,
        reason: 't',
      ));
      final view = projection.project(state());
      expect(view.phase, TodayPlanPhase.unavailable);
      expect(view.showKeepDayOpen, isTrue);
      expect(view.lexiBriefing, contains('No viable plan'));
    });
  });
}
