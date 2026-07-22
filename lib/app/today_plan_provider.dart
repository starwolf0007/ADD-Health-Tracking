// Riverpod composition for the Today plan proposal flow.
// Public surface is the locked interaction contract only.
// Initialization via injected seed; debug methods gated by pure-Dart capability.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/domain/day_plan.dart';
import 'package:neuroflow/executive/day_resolver.dart';
import 'package:neuroflow/executive/today_plan_state.dart';

/// Pure-Dart development capability. Production default is disabled.
class TodayPlanDevCapability {
  final bool enabled;

  const TodayPlanDevCapability({this.enabled = false});
}

final todayPlanDevCapabilityProvider =
    Provider<TodayPlanDevCapability>((ref) => const TodayPlanDevCapability());

/// Injected seed for provider initialization (tests override this).
sealed class TodayPlanSeed {
  const TodayPlanSeed();
}

final class TodayPlanSeedLoading extends TodayPlanSeed {
  const TodayPlanSeedLoading();
}

final class TodayPlanSeedUnavailable extends TodayPlanSeed {
  final InvalidScheduleRule error;
  final DayPlan? basePlan;

  const TodayPlanSeedUnavailable({
    required this.error,
    this.basePlan,
  });
}

final class TodayPlanSeedReady extends TodayPlanSeed {
  final DayPlan basePlan;
  final DayPlan proposal;
  final bool needsAttention;

  const TodayPlanSeedReady({
    required this.basePlan,
    required this.proposal,
    this.needsAttention = false,
  });
}

final todayPlanSeedProvider =
    Provider<TodayPlanSeed>((ref) => const TodayPlanSeedLoading());

/// Scenario fixtures for gated seeding.
class TodayPlanFixtures {
  const TodayPlanFixtures._();

  static DayPlan baseAnchors() => const DayPlan(blocks: [
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

  static DayPlan forScenario(MockDayScenario scenario) {
    final base = baseAnchors();
    switch (scenario) {
      case MockDayScenario.normalWorkday:
        return DayPlan(blocks: [
          ...base.blocks,
          const PlanBlock(
            id: 'commute-home',
            title: 'Commute Home',
            startMinutes: 870,
            endMinutes: 890,
            kind: PlanBlockKind.commute,
            isLocked: true,
            decision: ProposalDecision.notApplicable,
          ),
          const PlanBlock(
            id: 'recovery',
            title: 'Recovery Buffer',
            startMinutes: 890,
            endMinutes: 930,
            kind: PlanBlockKind.recoveryBuffer,
            explanation: 'Decompress after shift',
          ),
          const PlanBlock(
            id: 'gym',
            title: 'Gym',
            startMinutes: 930,
            endMinutes: 1000,
            kind: PlanBlockKind.flex,
          ),
          const PlanBlock(
            id: 'runway',
            title: 'Dinner Runway',
            startMinutes: 1000,
            endMinutes: 1020,
            kind: PlanBlockKind.runway,
            explanation: 'Clear counter, pull ingredients',
          ),
          const PlanBlock(
            id: 'dinner',
            title: 'Prep Zuppa Toscana',
            startMinutes: 1020,
            endMinutes: 1110,
            kind: PlanBlockKind.flex,
          ),
        ]);
      case MockDayScenario.overloadedDay:
        return DayPlan(blocks: [
          ...base.blocks,
          const PlanBlock(
            id: 'commute-home',
            title: 'Commute Home',
            startMinutes: 870,
            endMinutes: 890,
            kind: PlanBlockKind.commute,
            isLocked: true,
            decision: ProposalDecision.notApplicable,
          ),
          const PlanBlock(
            id: 'recovery',
            title: 'Recovery Buffer',
            startMinutes: 890,
            endMinutes: 915,
            kind: PlanBlockKind.recoveryBuffer,
          ),
          const PlanBlock(
            id: 'unifi',
            title: 'UniFi Network Troubleshooting',
            startMinutes: 915,
            endMinutes: 1005,
            kind: PlanBlockKind.flex,
          ),
          const PlanBlock(
            id: 'bambu',
            title: 'Bambu X2D Maintenance',
            startMinutes: 1005,
            endMinutes: 1065,
            kind: PlanBlockKind.flex,
          ),
        ]);
      case MockDayScenario.lowEnergyDay:
        return DayPlan(blocks: [
          ...base.blocks,
          const PlanBlock(
            id: 'commute-home',
            title: 'Commute Home',
            startMinutes: 870,
            endMinutes: 890,
            kind: PlanBlockKind.commute,
            isLocked: true,
            decision: ProposalDecision.notApplicable,
          ),
          const PlanBlock(
            id: 'recovery',
            title: 'Extended Recovery Buffer',
            startMinutes: 890,
            endMinutes: 990,
            kind: PlanBlockKind.recoveryBuffer,
          ),
          const PlanBlock(
            id: 'open',
            title: 'Open Space',
            startMinutes: 990,
            endMinutes: 1080,
            kind: PlanBlockKind.openSpace,
            decision: ProposalDecision.notApplicable,
          ),
        ]);
      case MockDayScenario.lateAppointment:
        return DayPlan(blocks: [
          base.blocks[0],
          base.blocks[1],
          const PlanBlock(
            id: 'leak',
            title: 'Emergency Leak Review',
            startMinutes: 870,
            endMinutes: 945,
            kind: PlanBlockKind.anchor,
            isLocked: true,
            decision: ProposalDecision.notApplicable,
            explanation: 'Unexpected late assignment',
          ),
          const PlanBlock(
            id: 'commute-delayed',
            title: 'Commute Home (Delayed)',
            startMinutes: 945,
            endMinutes: 965,
            kind: PlanBlockKind.commute,
            isLocked: true,
            decision: ProposalDecision.notApplicable,
          ),
          const PlanBlock(
            id: 'recovery-shifted',
            title: 'Recovery Buffer (Shifted)',
            startMinutes: 965,
            endMinutes: 1005,
            kind: PlanBlockKind.recoveryBuffer,
          ),
        ]);
    }
  }
}

class TodayPlanNotifier extends Notifier<TodayPlanState> {
  @override
  TodayPlanState build() {
    final seed = ref.watch(todayPlanSeedProvider);
    return switch (seed) {
      TodayPlanSeedLoading() => const TodayPlanLoading(),
      TodayPlanSeedUnavailable(:final error, :final basePlan) =>
          TodayPlanUnavailable(error: error, basePlan: basePlan),
      TodayPlanSeedReady(:final basePlan, :final proposal, :final needsAttention) =>
          buildReady(
            base: basePlan,
            proposal: proposal,
            needsAttention: needsAttention,
          ),
    };
  }

  bool get _devEnabled =>
      ref.read(todayPlanDevCapabilityProvider).enabled;

  // ---- Locked contract surface (safe no-ops outside valid Ready) ----

  void acceptDay() => state = transitionAcceptDay(state);

  void startReview() => state = transitionStartReview(state);

  void toggleBlock(String id) => state = transitionToggleBlock(state, id);

  void finishReview() => state = transitionFinishReview(state);

  void keepOriginal() => state = transitionKeepOriginal(state);

  void notNow() => state = transitionNotNow(state);

  void undo() => state = transitionUndo(state);

  void keepDayOpen() => state = transitionKeepDayOpen(state);

  // ---- Development-only (no-op unless capability enabled) ----

  void loadScenario(MockDayScenario scenario) {
    if (!_devEnabled) return;
    final base = TodayPlanFixtures.baseAnchors();
    final proposal = TodayPlanFixtures.forScenario(scenario);
    state = buildReady(base: base, proposal: proposal);
  }

  void simulateDisruption() {
    if (!_devEnabled) return;
    final current = state;
    if (current is! TodayPlanReady) return;
    final disrupted =
        TodayPlanFixtures.forScenario(MockDayScenario.lateAppointment);
    state = buildReady(
      base: current.basePlan,
      proposal: disrupted,
      needsAttention: true,
    );
  }
}

final todayPlanProvider =
    NotifierProvider<TodayPlanNotifier, TodayPlanState>(TodayPlanNotifier.new);
