// Riverpod composition for the Today plan proposal flow.
// Public surface is the locked interaction contract only.
// Development helpers are gated by an injected pure-Dart capability
// (no Flutter foundation dependency for gating).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/domain/day_plan.dart';
import 'package:neuroflow/executive/day_resolver.dart';
import 'package:neuroflow/executive/today_plan_state.dart';

/// Pure-Dart development capability. Production default is disabled.
/// Tests override via ProviderContainer to enable loadScenario / simulateDisruption.
class TodayPlanDevCapability {
  final bool enabled;

  const TodayPlanDevCapability({this.enabled = false});
}

final todayPlanDevCapabilityProvider =
    Provider<TodayPlanDevCapability>((ref) => const TodayPlanDevCapability());

/// Scenario fixtures for gated debug/test seeding.
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
  TodayPlanState build() => const TodayPlanLoading();

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

  /// Seeds a Ready proposal for the given scenario.
  void loadScenario(MockDayScenario scenario) {
    if (!_devEnabled) return;
    final base = TodayPlanFixtures.baseAnchors();
    final proposal = TodayPlanFixtures.forScenario(scenario);
    state = buildReady(base: base, proposal: proposal);
  }

  /// Forces a late-appointment disruption on the current Ready plan.
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

  /// Test-only path to Unavailable without public setters.
  void debugSetUnavailable(InvalidScheduleRule error) {
    if (!_devEnabled) return;
    final base = switch (state) {
      TodayPlanReady(:final basePlan) => basePlan,
      TodayPlanUnavailable(:final basePlan) => basePlan,
      _ => null,
    };
    state = TodayPlanUnavailable(error: error, basePlan: base);
  }
}

final todayPlanProvider =
    NotifierProvider<TodayPlanNotifier, TodayPlanState>(TodayPlanNotifier.new);
