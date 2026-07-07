// lib/presentation/widgets/reentry_card.dart
//
// Re-Entry Card — ADHD-friendly recovery UI for paused tasks.
// Phase 2 STAGE 3: Shows progress first, then context, then ask.
//
// Design: encourages friction-free re-entry with progress messaging.
// Dismissible (no persistent state change) and tappable to resume.

import 'package:flutter/material.dart';

import '../../domain/task.dart';
import '../../executive/reentry_advisor.dart';
import '../theme.dart';
import 'heartbeat_line.dart';

class ReentryCard extends StatelessWidget {
  /// The paused task to offer for re-entry.
  final Task task;

  /// Called when user taps "Resume →" button.
  final Function() onResume;

  /// Called when user dismisses the card (closes it).
  final Function() onDismiss;

  const ReentryCard({
    required this.task,
    required this.onResume,
    required this.onDismiss,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Analyze the paused task to extract re-entry hints.
    final advisor = ReentryAdvisor();
    final data = advisor.analyzeTask(task);

    // Progress as a 0-1 fraction for the heartbeat line.
    final progressFraction = (data.progressPercent / 100).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: icon + title
            Row(
              children: [
                const Icon(
                  Icons.pause_circle_outline,
                  size: 18,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resume: ${task.title}',
                    style: AppTextStyles.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Progress: show wins first — "X of Y steps done (XX%)"
            Row(
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  '${data.progressPercent}% progress',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Progress bar (using heartbeat line pattern).
            HeartbeatLine(value: progressFraction),

            const SizedBox(height: 12),

            // Context: where they paused
            if (data.pausedAtStep != null) ...[
              Row(
                children: [
                  const Icon(
                    Icons.pause,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Paused at: "${data.pausedAtStep}"',
                      style: AppTextStyles.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],

            // Next action: one small step to restart
            Row(
              children: [
                const Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Next: ${data.suggestedAction}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Action buttons: Dismiss + Resume
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onDismiss,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.textMuted,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.arrow_back,
                            size: 14,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Go back',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: onResume,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Resume',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.background,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.arrow_forward,
                            size: 14,
                            color: AppColors.background,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
