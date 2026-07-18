// lib/presentation/habits_widget.dart
//
// Habit check-in widget — embeds in Today screen below the task area.
// Shows up to 3 active habits (ADHD: fewer is better).
// Each row: habit name + streak count + tap-to-check circle.
//
// Design rules:
//   • Streak is shown as a number + flame glyph, not a progress bar (no anxiety).
//   • Checking is reversible (tap again to uncheck) — no permanence pressure.
//   • No guilt language anywhere in this file.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/domain/habit.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/presentation/theme.dart';

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
        // Cap at 3 — ADHD principle: don't overwhelm.
        final shown = habits.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Habits', style: AppTextStyles.bodySmall),
            ),
            ...shown.map((h) => _HabitRow(habit: h)),
            if (habits.length > 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
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
// Individual habit row
// ---------------------------------------------------------------------------

class _HabitRow extends ConsumerWidget {
  final Habit habit;

  const _HabitRow({required this.habit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final checked = habit.isCheckedToday;
    final streak = habit.currentStreak;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Check circle — tap to toggle
            GestureDetector(
              onTap: () => _toggle(ref),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: checked ? AppColors.accent : Colors.transparent,
                  border: Border.all(
                    color: checked ? AppColors.accent : AppColors.textMuted,
                    width: 1.5,
                  ),
                ),
                child: checked
                    ? const Icon(Icons.check,
                        size: 14, color: AppColors.background)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              child: Text(
                habit.name,
                style: AppTextStyles.bodyMedium.copyWith(
                  color:
                      checked ? AppColors.textSecondary : AppColors.textPrimary,
                  decoration: checked ? TextDecoration.lineThrough : null,
                  decorationColor: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Streak
            if (streak > 0) _StreakBadge(streak: streak),
          ],
        ),
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref) async {
    final repo = ref.read(habitRepositoryProvider);
    if (habit.isCheckedToday) {
      await repo.uncheckToday(habit.id);
    } else {
      await repo.checkIn(habit.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Streak badge
// ---------------------------------------------------------------------------

class _StreakBadge extends StatelessWidget {
  final int streak;

  const _StreakBadge({required this.streak});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Flame-like glyph — monochrome per §13 (no colour coding)
        const Icon(Icons.local_fire_department_outlined,
            size: 13, color: AppColors.textMuted),
        const SizedBox(width: 2),
        Text(
          '$streak',
          style: AppTextStyles.monoSmall,
        ),
      ],
    );
  }
}
