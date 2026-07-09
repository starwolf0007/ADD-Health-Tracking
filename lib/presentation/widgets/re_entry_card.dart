// lib/presentation/widgets/re_entry_card.dart
//
// PHASE 2 · STAGE 3 — the Re-Entry Card.
//
// "Tasks don't fail. They pause." This card is the calm, no-guilt landing
// spot for whatever got interrupted — it reads `interruptedTasksProvider`
// (paused/blocked tasks, most-recently-paused first) and offers a single,
// low-pressure way back in: Resume.
//
// Read-only projection (DEC-004): this widget never persists an "event". Its
// only write is the existing `TaskRepository.save` state transition, fired
// when the person taps Resume.
//
// On a calm day with nothing interrupted, this card renders nothing — the
// app stays quiet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/task.dart';
import '../theme.dart';

class ReEntryCard extends ConsumerWidget {
  const ReEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interrupted = ref.watch(interruptedTasksProvider).valueOrNull;

    if (interrupted == null || interrupted.isEmpty) {
      return const SizedBox.shrink();
    }

    final shown = interrupted.take(2).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.lg, AppSpace.xl, 0),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pick up where you left off', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpace.sm),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: AppSpace.md),
              const Divider(),
              const SizedBox(height: AppSpace.md),
            ],
            _ReEntryRow(task: shown[i]),
          ],
        ],
      ),
    );
  }
}

class _ReEntryRow extends ConsumerWidget {
  final Task task;

  const _ReEntryRow({required this.task});

  String? get _hint {
    if (task.pausedStep != null) return 'You stopped at: ${task.pausedStep}';
    if (task.pausedNote != null) return task.pausedNote;
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hint = _hint;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.attentionWash,
                      borderRadius: BorderRadius.circular(AppSpace.radiusInput),
                    ),
                    child: Text(
                      task.state.label,
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.attention),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(task.title, style: AppTextStyles.bodyMedium),
              const SizedBox(height: AppSpace.xs),
              Text(
                hint ?? 'Pick up where you left off.',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpace.md),
        TextButton(
          onPressed: () {
            ref
                .read(taskRepositoryProvider)
                .save(task.transitionTo(TaskState.inProgress));
          },
          style: TextButton.styleFrom(foregroundColor: AppColors.accent),
          child: const Text('Resume'),
        ),
      ],
    );
  }
}
