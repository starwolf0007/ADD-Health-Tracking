// lib/presentation/reflect_screen.dart
//
// Unlock Sprint surface 2: Reflect — calm mood check-in + recent history.
// Mood is on-device only (§2.8). Low/rough check-ins drive Quick Wins on Today.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/mood_providers.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/executive/planner.dart';
import 'package:neuroflow/presentation/theme.dart';

class ReflectScreen extends ConsumerWidget {
  const ReflectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayMoodProvider);
    final recentAsync = ref.watch(recentMoodsProvider);
    final todayPlan = ref.watch(todayControllerProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reflect'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.xxl,
        ),
        children: [
          Text(
            'How are you right now?',
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            'A rough or low check-in gently shifts Today toward Quick Wins. '
            'No scores shown — just a calm signal.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpace.xl),
          todayAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            ),
            error: (e, _) => Text(
              'Could not load today’s check-in.\n$e',
              style: AppTextStyles.bodySmall,
            ),
            data: (today) => _TodayMoodBlock(
              today: today,
              quickWinsAvailable: _quickWinsAvailable(todayPlan),
            ),
          ),
          const SizedBox(height: AppSpace.xxl),
          const Text('RECENT', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.md),
          recentAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpace.lg),
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
            ),
            error: (e, _) => Text(
              'Could not load history.\n$e',
              style: AppTextStyles.bodySmall,
            ),
            data: (logs) {
              if (logs.isEmpty) {
                return Text(
                  'No check-ins yet. The first one is enough.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textMuted,
                  ),
                );
              }
              return Column(
                children: [
                  for (final log in logs) ...[
                    _MoodHistoryTile(log: log),
                    const SizedBox(height: AppSpace.sm),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TodayMoodBlock extends ConsumerWidget {
  final MoodLog? today;
  final bool quickWinsAvailable;

  const _TodayMoodBlock({
    required this.today,
    required this.quickWinsAvailable,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (today != null) ...[
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpace.radiusCard),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today: ${today!.level.label}',
                        style: AppTextStyles.titleMedium,
                      ),
                      if (today!.note != null && today!.note!.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xs),
                        Text(today!.note!, style: AppTextStyles.bodySmall),
                      ],
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        _formatTime(today!.loggedAt),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (today!.level.triggersQuickWins && quickWinsAvailable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.sm,
                      vertical: AppSpace.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentWash,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Quick Wins',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            'Log another if things shifted',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final level in MoodLevel.values)
              _MoodChip(
                level: level,
                selected: today?.level == level,
                onTap: () => _logMood(context, ref, level),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _logMood(
    BuildContext context,
    WidgetRef ref,
    MoodLevel level,
  ) async {
    HapticFeedback.selectionClick();
    final note = await _optionalNoteSheet(context);
    try {
      await ref.read(moodRepositoryProvider).log(
            MoodLog.create(level, note: note),
          );
      ref.invalidate(todayControllerProvider);
      TodayState? derivedPlan;
      try {
        derivedPlan = await ref.read(todayControllerProvider.future);
      } catch (error, stackTrace) {
        // The mood was saved successfully. A plan-refresh failure must not
        // turn that successful check-in into a false save-error message.
        debugPrint('Could not refresh Today after mood check-in: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (!context.mounted) return;
      final quickWinsAvailable = _quickWinsAvailable(derivedPlan);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            level.triggersQuickWins
                ? quickWinsAvailable
                    ? 'Logged ${level.label}. Today will lean toward Quick Wins.'
                    : 'Logged ${level.label}. Nothing is pending right now.'
                : 'Logged ${level.label}.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Could not log mood: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save check-in. Try again.')),
      );
    }
  }

  Future<String?> _optionalNoteSheet(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpace.xl,
            AppSpace.lg,
            AppSpace.xl,
            AppSpace.lg + bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Anything to note? (optional)',
                  style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Optional — skip if you prefer',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    final trimmed = result?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $period';
  }
}

bool _quickWinsAvailable(TodayState? state) =>
    state != null &&
    state.mode == DayMode.quickWins &&
    state.quickWins.isNotEmpty;

class _MoodChip extends StatelessWidget {
  final MoodLevel level;
  final bool selected;
  final VoidCallback onTap;

  const _MoodChip({
    required this.level,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentWash : AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppSpace.radiusInput),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        child: Container(
          constraints: const BoxConstraints(minWidth: 72, minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.md,
          ),
          alignment: Alignment.center,
          child: Text(
            level.label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: selected ? AppColors.accent : AppColors.textPrimary,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _MoodHistoryTile extends StatelessWidget {
  final MoodLog log;

  const _MoodHistoryTile({required this.log});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(log.level.label, style: AppTextStyles.bodyMedium),
              ),
              Text(
                _formatDay(log.loggedAt),
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          if (log.note != null && log.note!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(log.note!, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }

  String _formatDay(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return '${dt.month}/${dt.day}';
  }
}
