// lib/intelligence/planning_context.dart
//
// Typed snapshot of what the planner knew — prompts are built from this,
// never from ad-hoc string soup at call sites. Lives in its own file so
// both the advisor and the config can import it without a cycle.

import '../domain/task.dart';
import '../executive/planner.dart';

class PlanningContext {
  final DayMode mode;

  /// Top pending tasks (already deterministically ordered by the Executive's
  /// energy-ascending sort). Capped to 5 in the prompt.
  final List<Task> topPending;

  const PlanningContext({required this.mode, required this.topPending});

  factory PlanningContext.fromPlan(Plan plan, List<Task> allPending) {
    return PlanningContext(
      mode: plan.mode,
      topPending: allPending.take(5).toList(),
    );
  }
}
