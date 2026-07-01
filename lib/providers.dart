// lib/providers.dart
//
// Riverpod composition root. Wires the four-layer architecture:
//   Platform  (database)
//   ↓
//   Data      (repository)
//   ↓
//   Executive (planner + advisor seam)
//   ↓
//   Presentation (TodayController → TodayState)
//
// Rule: TodayController is the SOLE call site for PlanAdvisor.refine().
// Executive.evaluate() is pure/synchronous; the async AI seam lives here.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database.dart';
import 'data/habit_repository.dart';
import 'data/habit_repository_impl.dart';
import 'data/routine_repository.dart';
import 'data/routine_repository_impl.dart';
import 'data/task_repository.dart';
import 'data/task_repository_impl.dart';
import 'domain/habit.dart';
import 'domain/routine.dart';
import 'domain/task.dart';
import 'executive/lexi_plan_advisor.dart';
import 'executive/planner.dart';

// ---------------------------------------------------------------------------
// Platform layer
// ---------------------------------------------------------------------------

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ---------------------------------------------------------------------------
// Data layer
// ---------------------------------------------------------------------------

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  return DriftTaskRepository(ref.watch(databaseProvider));
});

final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  return DriftRoutineRepository(ref.watch(databaseProvider));
});

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  return DriftHabitRepository(ref.watch(databaseProvider));
});

// ---------------------------------------------------------------------------
// Executive layer
// ---------------------------------------------------------------------------

final executiveProvider = Provider<Executive>((ref) => Executive());

// ---------------------------------------------------------------------------
// AI advisor tier (§14)
// ---------------------------------------------------------------------------

enum AdvisorTier {
  /// Phase 1: fully deterministic, no AI. Default.
  none,
  /// Phase 2: on-device Gemini Nano via platform channel. Default when available.
  lexi,
  /// Phase 3: cloud Gemini — explicit user opt-in only, never default.
  cloud,
}

/// User's chosen advisor tier. Defaults to lexi (gracefully falls back to NoOp
/// if Gemini Nano is unavailable on the device).
final advisorTierProvider = StateProvider<AdvisorTier>((ref) {
  return AdvisorTier.lexi; // will silently NoOp until native bridge is wired
});

/// Active PlanAdvisor — swaps based on advisorTierProvider.
/// TodayController is the SOLE call site for refine().
final planAdvisorProvider = Provider<PlanAdvisor>((ref) {
  final tier = ref.watch(advisorTierProvider);
  switch (tier) {
    case AdvisorTier.lexi:
      return LexiPlanAdvisor();
    case AdvisorTier.cloud:
      // TODO(phase3): read API key from FlutterSecureStorage before constructing
      return const CloudGeminiPlanAdvisor(apiKey: null);
    case AdvisorTier.none:
      return const NoOpPlanAdvisor();
  }
});

// ---------------------------------------------------------------------------
// TodayState — what the Presentation layer consumes
// ---------------------------------------------------------------------------

class TodayState {
  final DayMode mode;
  final Task? primaryTask;
  final List<Task> quickWins;
  final String reason;
  final bool isLoading;

  const TodayState({
    this.mode = DayMode.normal,
    this.primaryTask,
    this.quickWins = const [],
    this.reason = '',
    this.isLoading = true,
  });

  TodayState copyWith({
    DayMode? mode,
    Task? primaryTask,
    List<Task>? quickWins,
    String? reason,
    bool? isLoading,
  }) {
    return TodayState(
      mode: mode ?? this.mode,
      primaryTask: primaryTask ?? this.primaryTask,
      quickWins: quickWins ?? this.quickWins,
      reason: reason ?? this.reason,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// ---------------------------------------------------------------------------
// TodayController — the Presentation ↔ Executive bridge
// ------------------------------