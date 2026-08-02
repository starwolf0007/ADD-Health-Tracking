// lib/presentation/widgets/due_routines_card.dart
//
// Surfaces routines that are due right now on Today so morning/evening
// entry does not require switching tabs. Uses existing dueRoutinesProvider
// + launchRoutine — presentation only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/presentation/routine_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

/// Shows at most a few due, incomplete routines with a single Start action.
/// Hidden when nothing is due. No streak/count/progress figures (§13).
class DueRoutinesCard extends ConsumerWidget {
  const DueRoutinesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueAsync = ref.watch(dueRoutinesProvider);

    return dueAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (routines) {
        if (routines.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final routine in routines.take(2)) ...[
              _DueRoutineTile(routine: routine),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        );
      },
    );
  }
}

class _DueRoutineTile extends ConsumerWidget {
  final Routine routine;

  const _DueRoutineTile({required this.routine});

  String get _subtitle {
    final step = routine.activeStep;
    if (step == null) return 'Ready when you are';
    return 'Next: ${step.title}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.surfaceRaised,
      borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      child: InkWell(
        key: ValueKey('due-routine-${routine.id}'),
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        onTap: () => _launch(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              const Icon(Icons.repeat_rounded, color: AppColors.accent),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Routine',
                      style: AppTextStyles.label.copyWith(
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(routine.name, style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppSpace.xs),
                    Text(_subtitle, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () => _launch(context, ref),
                child: const Text('Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launch(BuildContext context, WidgetRef ref) async {
    await launchRoutine(context, routine);
    ref.invalidate(dueRoutinesProvider);
  }
}
