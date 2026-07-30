// lib/presentation/widgets/quick_wins_panel.dart
//
// §6: Quick Wins is a reshaped state of Today — containment is the feature.
// Renders the Executive-selected list (≤3) with calm, non-shame language.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/presentation/theme.dart';

class QuickWinsPanel extends ConsumerWidget {
  final List<Task> tasks;
  final String reason;

  const QuickWinsPanel({
    super.key,
    required this.tasks,
    required this.reason,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.accentWash,
            borderRadius: BorderRadius.circular(AppSpace.radiusCard),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Wins',
                style: AppTextStyles.label.copyWith(color: AppColors.accent),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                reason.isNotEmpty
                    ? reason
                    : 'Lighter load today — a few small steps are enough.',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Nothing else is tracked today.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (tasks.isEmpty)
          Text(
            'No pending tasks. Rest is a valid next step.',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
          )
        else
          for (final task in tasks) ...[
            _QuickWinTile(task: task),
            const SizedBox(height: AppSpace.sm),
          ],
      ],
    );
  }
}

class _QuickWinTile extends ConsumerWidget {
  final Task task;

  const _QuickWinTile({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(taskActionControllerProvider);
    final isActive = task.status == TaskStatus.inProgress;
    final isPaused = task.status == TaskStatus.paused;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: AppTextStyles.titleMedium),
          if (task.notes?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpace.xs),
            Text(task.notes!, style: AppTextStyles.bodySmall),
          ],
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton(
                onPressed: isActive
                    ? null
                    : () async {
                        try {
                          if (isPaused) {
                            await actions.resume(task.id);
                          } else {
                            await actions.start(task.id);
                          }
                        } on TaskActionFailure catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Could not ${error.action}. Try again.',
                              ),
                            ),
                          );
                        }
                      },
                child: Text(
                  isPaused
                      ? 'Resume'
                      : isActive
                          ? 'Running'
                          : 'Start',
                ),
              ),
              TextButton(
                onPressed: () => actions.notNow(task.id),
                child: const Text('Not now'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
