// lib/presentation/today_screen.dart
//
// Today screen — the single surface users see on open.
// Consumes todayControllerProvider (AsyncNotifier) and renders:
//   • Normal mode  : Next Best Action card + reason line
//   • Quick Wins   : ≤3 low-effort task cards with reassurance line
//   • Empty        : All-clear state
//   • Heartbeat    : Live completed-today count (mono font, state-transition
//                    only — no idle animation per spec v1.3)
//   • FAB          : Capture sheet (§13 — one gesture from anywhere)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/executive/planner.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/presentation/habits_widget.dart';
import 'package:neuroflow/presentation/routine_screen.dart';
import 'package:neuroflow/presentation/settings_screen.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/widgets/capture_sheet.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayControllerProvider);
    final completedAsync = ref.watch(completedTodayCountProvider);
    final nameAsync = ref.watch(displayNameProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: _GreetingHeader(nameAsync: nameAsync),
        actions: [
          // Heartbeat count lives in trailing position — §13 token
          _HeartbeatCount(completedAsync: completedAsync),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: AppColors.textSecondary, size: 20),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: todayAsync.when(
        loading: () => const _LoadingBody(),
        error: (e, _) => _ErrorBody(error: e),
        data: (state) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TodayBody(state: state),
              const _DueRoutinesSection(),
              const SizedBox(height: 8),
              const HabitsWidget(),
              const SizedBox(height: 100), // FAB clearance
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCaptureSheet(context),
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _GreetingHeader extends StatelessWidget {
  final AsyncValue<String> nameAsync;

  const _GreetingHeader({required this.nameAsync});

  @override
  Widget build(BuildContext context) {
    final name = nameAsync.value ?? '';
    final greeting = name.isNotEmpty ? 'Hey, $name' : 'Today';
    return Text(
      greeting,
      style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
    );
  }
}

class _HeartbeatCount extends StatelessWidget {
  final AsyncValue<int> completedAsync;

  const _HeartbeatCount({required this.completedAsync});

  @override
  Widget build(BuildContext context) {
    final count = completedAsync.value ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline,
            size: 14, color: count > 0 ? AppColors.accent : AppColors.textMuted),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: AppTextStyles.monoSmall.copyWith(
            color: count > 0 ? AppColors.accent : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Body states
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final Object error;

  const _ErrorBody({required this.error});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'Something went wrong. Try restarting the app.',
          style: AppTextStyles.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  final TodayState state;

  const _TodayBody({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state.mode) {
      DayMode.quickWins => _QuickWinsBody(state: state, ref: ref),
      DayMode.normal => state.primaryTask == null
          ? const _AllClearBody()
          : _NormalBody(state: state, ref: ref),
    };
  }
}

// ---------------------------------------------------------------------------
// Normal mode
// ---------------------------------------------------------------------------

class _NormalBody extends StatelessWidget {
  final TodayState state;
  final WidgetRef ref;

  const _NormalBody({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final task = state.primaryTask!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Next up', style: AppTextStyles.bodySmall),
          const SizedBox(height: 12),
          _TaskCard(task: task, onComplete: () {
            ref.read(todayControllerProvider.notifier).complete(task.id);
          }),
          if (state.reason.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(state.reason, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Wins mode
// ---------------------------------------------------------------------------

class _QuickWinsBody extends StatelessWidget {
  final TodayState state;
  final WidgetRef ref;

  const _QuickWinsBody({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.reason,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          ...state.quickWins.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskCard(
                task: task,
                onComplete: () {
                  ref.read(todayControllerProvider.notifier).complete(task.id);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All clear
// ---------------------------------------------------------------------------

class _AllClearBody extends StatelessWidget {
  const _AllClearBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 48, color: AppColors.accent.withValues(alpha: 0.6)),
          const SizedBox(height: 16),
          const Text('All clear', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          const Text('Nothing pending — add something with +',
              style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task card
// ---------------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onComplete;

  const _TaskCard({required this.task, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _EnergyGlyph(energy: task.energy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: AppTextStyles.bodyMedium),
                if (task.notes != null && task.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(task.notes!, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onComplete,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textMuted, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.check,
                  size: 16, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// Energy glyph — monochrome, shape-distinguished (no colour coding per §13)
class _EnergyGlyph extends StatelessWidget {
  final EnergyLevel energy;

  const _EnergyGlyph({required this.energy});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (energy) {
      EnergyLevel.low => (Icons.remove, 'low'),
      EnergyLevel.medium => (Icons.circle_outlined, 'medium'),
      EnergyLevel.high => (Icons.keyboard_arrow_up, 'high'),
    };
    return Semantics(
      label: '$label energy',
      child:
          Icon(icon, size: 18, color: AppColors.textSecondary),
    );
  }
}

// ---------------------------------------------------------------------------
// Due routines section — shown between tasks and habits
// ---------------------------------------------------------------------------

/// Shows routines that are due right now (time-of-day aware).
/// Hidden when no routines are due — zero visual noise.
class _DueRoutinesSection extends ConsumerWidget {
  const _DueRoutinesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueAsync = ref.watch(dueRoutinesProvider);

    return dueAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (routines) {
        if (routines.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Routines', style: AppTextStyles.bodySmall),
            ),
            ...routines.map(
              (r) => _RoutineCard(
                routine: r,
                onTap: () => launchRoutine(context, r),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Single tappable routine card.
/// Shows progress state when a routine is already in progress.
class _RoutineCard extends StatelessWidget {
  final Routine routine;
  final VoidCallback onTap;

  const _RoutineCard({required this.routine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inProgress = routine.completedCount > 0 && !routine.isComplete;
    final totalMinutes = routine.steps.fold<int>(
      0,
      (sum, s) => sum + (s.durationMinutes ?? 0),
    );
    final stepLabel = inProgress
        ? '${routine.completedCount} / ${routine.steps.length} steps'
        : '${routine.steps.length} steps · ~$totalMinutes min';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            // Accent border when already in progress — signals continuation
            border: inProgress
                ? Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    width: 1,
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.name, style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 2),
                    Text(stepLabel, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Text(
                inProgress ? 'Continue' : 'Start',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.accent),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
