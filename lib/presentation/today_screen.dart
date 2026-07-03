// lib/presentation/today_screen.dart
//
// Today — the single surface users see on open (§13).
//
// Redesign principles (all within locked v1.3 tokens):
//   • ONE thing dominates. In normal mode the Next Best Action is a full
//     display-scale card; everything else on screen is quiet. The app's whole
//     pitch is "here is the one thing" — the layout now says that too.
//   • Heartbeat line is real. The built HeartbeatLine widget was orphaned;
//     it now sits under the header, filled by completed ÷ (completed+pending),
//     updating only on state transitions (no idle motion).
//   • Completion gives feedback. Marking done shows a one-line snackbar with
//     the day's count — small dopamine, no confetti, calm-functional.
//   • Quick Wins mode LOOKS lighter: reassurance line + up to three small
//     cards instead of one big one.
//   • Every tap target ≥ 48px. Complete controls are real InkWells with
//     ripple + semantics, not bare GestureDetectors.
//   • Zero widget duplication: EnergyGlyph, HeartbeatLine, and the capture
//     sheet come from widgets/ — the former inline copies are deleted.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/focus_timer.dart';
import '../app/providers.dart';
import '../domain/routine.dart';
import '../domain/task.dart';
import '../executive/planner.dart';
import 'routine_screen.dart';
import 'theme.dart';
import 'widgets/capture_sheet.dart';
import 'widgets/energy_glyph.dart';
import 'widgets/heartbeat_line.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(todayControllerProvider);
    final completed = ref.watch(completedTodayCountProvider).valueOrNull ?? 0;
    final pending =
        ref.watch(pendingTasksProvider).valueOrNull?.length ?? 0;
    final total = completed + pending;
    final fraction = total == 0 ? 0.0 : completed / total;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const _Header(),
        actions: [
          _HeartbeatCount(count: completed),
          const SizedBox(width: AppSpace.xl),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(11),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.xl, 0, AppSpace.xl, AppSpace.sm),
            child: HeartbeatLine(value: fraction),
          ),
        ),
      ),
      body: planAsync.when(
        loading: () => const _LoadingBody(),
        error: (e, _) => _ErrorBody(
          onRetry: () => ref.invalidate(todayControllerProvider),
        ),
        data: (plan) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PlanBody(plan: plan),
              const _DueRoutinesSection(),
              const SizedBox(height: 100), // FAB clearance
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showCaptureSheet(context),
        tooltip: 'Capture a task',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — title + date anchor
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header();

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Today', style: AppTextStyles.titleMedium),
        const SizedBox(height: 2),
        Text(
          '${_days[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}',
          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _HeartbeatCount extends StatelessWidget {
  final int count;

  const _HeartbeatCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final active = count > 0;
    final color = active ? AppColors.accent : AppColors.textMuted;
    return Semantics(
      label: '$count completed today',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline, size: 15, color: color),
          const SizedBox(width: AppSpace.xs),
          Text('$count', style: AppTextStyles.monoSmall.copyWith(color: color)),
        ],
      ),
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
  final VoidCallback onRetry;

  const _ErrorBody({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Today's plan didn't load.",
                style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.lg),
            TextButton(
              onPressed: onRetry,
              child: const Text('Try again',
                  style: TextStyle(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanBody extends ConsumerWidget {
  final Plan plan;

  const _PlanBody({required this.plan});

  void _complete(BuildContext context, WidgetRef ref, Task task) {
    ref.read(todayControllerProvider.notifier).complete(task.id);
    final done =
        (ref.read(completedTodayCountProvider).valueOrNull ?? 0) + 1;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const Icon(Icons.check, size: 16, color: AppColors.accent),
            const SizedBox(width: AppSpace.sm),
            Text('Done — $done today',
                style: AppTextStyles.bodyMedium),
          ],
        ),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (plan.mode) {
      DayMode.quickWins => _QuickWinsBody(
          plan: plan,
          onComplete: (t) => _complete(context, ref, t),
        ),
      DayMode.normal => plan.primaryTask == null
          ? const _AllClearBody()
          : _NextBestAction(
              task: plan.primaryTask!,
              reason: plan.reason,
              onComplete: () => _complete(context, ref, plan.primaryTask!),
            ),
    };
  }
}

// ---------------------------------------------------------------------------
// Normal mode — the one thing, at full weight
// ---------------------------------------------------------------------------

class _NextBestAction extends ConsumerWidget {
  final Task task;
  final String reason;
  final VoidCallback onComplete;

  const _NextBestAction({
    required this.task,
    required this.reason,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(focusTimerProvider);
    final isThisTask = focus.isActive && focus.taskId == task.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.xl, AppSpace.xl, AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('NEXT UP', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpace.xl),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpace.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EnergyGlyph(task.energy, showLabel: true),
                const SizedBox(height: AppSpace.md),
                Text(task.title, style: AppTextStyles.displayLarge),
                if (task.notes != null && task.notes!.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(task.notes!, style: AppTextStyles.bodySmall),
                ],
                const SizedBox(height: AppSpace.xl),
                if (isThisTask)
                  _FocusTimerActive(focus: focus, onComplete: onComplete)
                else
                  _FocusTimerStart(task: task, onComplete: onComplete),
              ],
            ),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(reason, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Idle state: a "Done" action plus a "Start focus" affordance with the
/// task's own estimate (or a sensible default) as the first chip.
class _FocusTimerStart extends ConsumerWidget {
  final Task task;
  final VoidCallback onComplete;

  const _FocusTimerStart({required this.task, required this.onComplete});

  static const _options = [5, 15, 30, 60];

  void _start(WidgetRef ref, int minutes) {
    HapticFeedback.selectionClick();
    ref.read(focusTimerProvider.notifier).start(
          taskId: task.id,
          taskTitle: task.title,
          targetMinutes: minutes,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Seed the chip set with the task's estimate if it isn't already present.
    final est = task.estimatedMinutes;
    final options = <int>{
      if (est != null && est > 0) est,
      ..._options,
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: onComplete,
          child: const Text('Done'),
        ),
        const SizedBox(height: AppSpace.lg),
        const Row(
          children: [
            Icon(Icons.timer_outlined,
                size: 16, color: AppColors.textSecondary),
            SizedBox(width: AppSpace.sm),
            Text('Start a focus block', style: AppTextStyles.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final m in options)
              _MinuteChip(
                label: '$m min',
                highlighted: m == est,
                onTap: () => _start(ref, m),
              ),
          ],
        ),
      ],
    );
  }
}

/// Running/overtime state: big live numerals, a thin progress line, and a
/// single Done. Overtime is information, not judgment — numerals go amber,
/// copy stays kind.
class _FocusTimerActive extends ConsumerWidget {
  final FocusState focus;
  final VoidCallback onComplete;

  const _FocusTimerActive({required this.focus, required this.onComplete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overtime = focus.phase == FocusPhase.overtime;
    final numeralColor =
        overtime ? AppColors.attention : AppColors.textPrimary;

    final String clock;
    final String caption;
    if (overtime) {
      clock = formatFocusClock(focus.elapsed);
      final over = focus.overBy.inMinutes;
      caption = over <= 0
          ? 'At your mark — still yours.'
          : '$over over — still yours.';
    } else {
      clock = formatFocusClock(focus.elapsed);
      final left = focus.remaining.inMinutes;
      caption = 'Target ${focus.targetMinutes} min · ~$left left';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(clock,
              style: AppTextStyles.monoLarge.copyWith(color: numeralColor)),
        ),
        const SizedBox(height: AppSpace.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: focus.progress,
            minHeight: 3,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation(
                overtime ? AppColors.attention : AppColors.accent),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        Center(child: Text(caption, style: AppTextStyles.bodySmall)),
        const SizedBox(height: AppSpace.lg),
        ElevatedButton(
          onPressed: () {
            ref.read(focusTimerProvider.notifier).stop();
            onComplete();
          },
          child: const Text('Done'),
        ),
        const SizedBox(height: AppSpace.sm),
        TextButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            ref.read(focusTimerProvider.notifier).stop();
          },
          child: const Text('Stop timer'),
        ),
      ],
    );
  }
}

class _MinuteChip extends StatelessWidget {
  final String label;
  final bool highlighted;
  final VoidCallback onTap;

  const _MinuteChip({
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? AppColors.accentWash : AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppSpace.radiusInput),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: AppSpace.sm),
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: highlighted ? AppColors.accent : AppColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Wins mode — deliberately lighter
// ---------------------------------------------------------------------------

class _QuickWinsBody extends StatelessWidget {
  final Plan plan;
  final void Function(Task) onComplete;

  const _QuickWinsBody({required this.plan, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.xl, AppSpace.xl, AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('QUICK WINS', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.sm),
          Text(
            plan.reason,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.lg),
          ...plan.quickWins.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm + 2),
              child: _QuickWinCard(
                task: task,
                onComplete: () => onComplete(task),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickWinCard extends StatelessWidget {
  final Task task;
  final VoidCallback onComplete;

  const _QuickWinCard({required this.task, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      ),
      padding: const EdgeInsets.only(left: AppSpace.lg),
      child: Row(
        children: [
          EnergyGlyph(task.energy, size: 16),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
              child: Text(task.title,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
          ),
          _CompleteButton(onTap: onComplete, taskTitle: task.title),
        ],
      ),
    );
  }
}

/// 48px ripple target wrapping the check affordance.
class _CompleteButton extends StatelessWidget {
  final VoidCallback onTap;
  final String taskTitle;

  const _CompleteButton({required this.onTap, required this.taskTitle});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Mark "$taskTitle" done',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        child: SizedBox(
          width: AppSpace.tapTarget + AppSpace.sm,
          height: AppSpace.tapTarget + AppSpace.sm,
          child: Center(
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textMuted, width: 1.5),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.check,
                  size: 15, color: AppColors.textMuted),
            ),
          ),
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 72),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline,
              size: 44, color: AppColors.accent.withValues(alpha: 0.55)),
          const SizedBox(height: AppSpace.lg),
          const Text('All clear', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpace.xs),
          const Text('Nothing pending right now.', style: AppTextStyles.bodySmall),
          const SizedBox(height: AppSpace.xl),
          TextButton.icon(
            onPressed: () => showCaptureSheet(context),
            icon: const Icon(Icons.add, size: 18, color: AppColors.accent),
            label: const Text('Capture something',
                style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Due routines
// ---------------------------------------------------------------------------

class _DueRoutinesSection extends ConsumerWidget {
  const _DueRoutinesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueRoutinesProvider).valueOrNull ?? const <Routine>[];
    if (due.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding:
          const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.sm, AppSpace.xl, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ROUTINES', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.sm),
          ...due.map((r) => _RoutineRow(routine: r)),
        ],
      ),
    );
  }
}

class _RoutineRow extends ConsumerWidget {
  final Routine routine;

  const _RoutineRow({required this.routine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = '${routine.completedCount}/${routine.steps.length}';
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpace.radiusCard),
          onTap: () => launchRoutine(context, routine, onFinished: () {
            ref.invalidate(dueRoutinesProvider);
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpace.tapTarget),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg, vertical: AppSpace.md),
            child: Row(
              children: [
                const Icon(Icons.replay_outlined,
                    size: 17, color: AppColors.textSecondary),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(routine.name, style: AppTextStyles.bodyMedium),
                ),
                Text(progress, style: AppTextStyles.monoSmall),
                const SizedBox(width: AppSpace.sm),
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
