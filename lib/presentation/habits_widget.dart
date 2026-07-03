// lib/presentation/habits_widget.dart
//
// Habit check-in — embeds in Today below the task area.
// Shows up to 3 active habits (ADHD: fewer is better).
//
// Design rules:
//   • Streak = number + flame glyph, monochrome (§13) — not a progress bar.
//   • Checking is reversible — tap again to uncheck, no permanence pressure.
//   • No guilt language anywhere in this file.
//   • v-fix: check target expanded to a 48px ripple (was a bare 26px
//     GestureDetector — below the Android accessibility floor).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/habit.dart';
import 'theme.dart';

class HabitsWidget extends ConsumerWidget {
  const HabitsWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(activeHabitsProvider);

    return habitsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (habits) {
        if (habits.isEmpty) return const SizedBox.shrink();
        final shown = habits.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpace.xl, 0, AppSpace.xl, AppSpace.sm),
              child: Text('HABITS', style: AppTextStyles.label),
            ),
            ...shown.map((h) => _HabitRow(habit: h)),
            if (habits.length > 3)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(AppSpace.xl, 6, AppSpace.xl, 0),
                child: Text(
                  '+ ${habits.length - 3} more in settings',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textMuted),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Row
// ---------------------------------------------------------------------------

class _HabitRow extends ConsumerWidget {
  final Habit habit;

  const _HabitRow({required this.habit});

  Future<void> _toggle(WidgetRef ref) async {
    final repo = ref.read(habitRepositoryProvider);
    if (habit.isCheckedToday) {
      await repo.uncheckToday(habit.id);
    } else {
      await repo.checkIn(habit.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = habit.isCheckedToday;
    final streak = habit.currentStreak;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, 6),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        child: InkWell(
          // Whole row toggles — the biggest possible target.
          onTap: () => _toggle(ref),
          borderRadius: BorderRadius.circular(AppSpace.radiusInput),
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSpace.tapTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Row(
              children: [
                Semantics(
                  label: checked
                      ? '${habit.name}, done today. Tap to undo.'
                      : '${habit.name}, not done yet. Tap to check in.',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          checked ? AppColors.accent : Colors.transparent,
                      border: Border.all(
                        color:
                            checked ? AppColors.accent : AppColors.textMuted,
                        width: 1.5,
                      ),
                    ),
                    child: checked
                        ? const Icon(Icons.check,
                            size: 14, color: AppColors.background)
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    habit.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: checked
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                      decoration:
                          checked ? TextDecoration.lineThrough : null,
                      decorationColor: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                if (streak > 0) _StreakBadge(streak: streak),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Streak badge — monochrome per §13
// ---------------------------------------------------------------------------

class _StreakBadge extends StatelessWidget {
  final int streak;

  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.local_fire_department_outlined,
            size: 13, color: AppColors.textMuted),
        const SizedBox(width: 2),
        Text('$streak', style: AppTextStyles.monoSmall),
      ],
    );
  }
}
