// lib/presentation/reflect_screen.dart
//
// The Reflect tab (v2). Three quiet sections:
//   • Check-in — the 5-point mood row. A tap at Low or below flips Today
//     into Quick Wins (spec §6). §2.8: this data never leaves the device.
//   • This week — seven dots, filled by mood. No numbers, no judgment.
//   • Habits — the forgiveness-streak widget, relocated here so Today
//     stays a one-thing screen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/mood.dart';
import 'habits_widget.dart';
import 'theme.dart';

class ReflectScreen extends ConsumerWidget {
  const ReflectScreen({super.key});

  Future<void> _log(
      BuildContext context, WidgetRef ref, MoodLevel level) async {
    HapticFeedback.mediumImpact();
    await ref.read(moodRepositoryProvider).log(MoodLog.create(level));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(level.triggersQuickWins
            ? 'Logged. Today is switching to gentle wins.'
            : 'Logged.'),
      ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayMood = ref.watch(todayMoodProvider).valueOrNull;
    final recent = ref.watch(recentMoodsProvider).valueOrNull ?? const [];
    final doneToday =
        ref.watch(completedTodayCountProvider).valueOrNull ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Reflect'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xxl),
        children: [
          const Text('CHECK-IN', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpace.radiusCard),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("How's the engine running?",
                    style: AppTextStyles.titleMedium),
                const SizedBox(height: AppSpace.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final level in MoodLevel.values)
                      _MoodButton(
                        level: level,
                        selected: todayMood?.level == level,
                        onTap: () => _log(context, ref, level),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xxl),
          const Text('THIS WEEK', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.md),
          _WeekStrip(recent: recent),
          const SizedBox(height: AppSpace.xxl),
          const Text('HABITS', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.md),
          const HabitsWidget(),
          const SizedBox(height: AppSpace.xl),
          Center(
            child: Text(
              doneToday == 0
                  ? 'The day is still open.'
                  : '$doneToday done today.',
              style: AppTextStyles.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodButton extends StatelessWidget {
  final MoodLevel level;
  final bool selected;
  final VoidCallback onTap;

  const _MoodButton({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Fill deepens with level — shape carries meaning, color stays calm.
    final fill = AppColors.accent
        .withValues(alpha: 0.15 + 0.2 * level.index.toDouble());

    return Semantics(
      button: true,
      selected: selected,
      label: 'Mood: ${level.label}',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: AppSpace.tapTarget,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: Border.all(
                    color: selected ? AppColors.accent : AppColors.divider,
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                level.label,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 10,
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final List<MoodLog> recent;

  const _WeekStrip({required this.recent});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List.generate(7, (i) {
      final d = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: 6 - i));
      MoodLog? latest;
      for (final log in recent) {
        if (log.loggedAt.year == d.year &&
            log.loggedAt.month == d.month &&
            log.loggedAt.day == d.day) {
          latest = log; // recent is oldest-first; last match wins
        }
      }
      return (day: d, mood: latest);
    });

    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final entry in days)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.mood == null
                        ? Colors.transparent
                        : AppColors.accent.withValues(
                            alpha:
                                0.15 + 0.2 * entry.mood!.level.index),
                    border: Border.all(
                      color: entry.mood == null
                          ? AppColors.divider
                          : Colors.transparent,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  labels[(entry.day.weekday - 1) % 7],
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
