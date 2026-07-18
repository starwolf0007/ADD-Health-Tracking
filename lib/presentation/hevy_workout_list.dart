import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuroflow/app/hevy_providers.dart';
import 'package:neuroflow/data/hevy_repository.dart';
import 'package:neuroflow/presentation/theme.dart';

class HevyWorkoutList extends ConsumerWidget {
  const HevyWorkoutList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(recentHevyWorkoutsProvider).when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Recent workouts aren\'t available right now.',
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpace.sm),
              TextButton(
                onPressed: () => ref.invalidate(recentHevyWorkoutsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
          data: (workouts) => workouts.isEmpty
              ? const _EmptyWorkouts()
              : Column(
                  children: workouts
                      .map((workout) => HevyWorkoutTile(workout: workout))
                      .toList(growable: false),
                ),
        );
  }
}

class HevyWorkoutTile extends StatelessWidget {
  final HevyWorkoutSummary workout;

  const HevyWorkoutTile({super.key, required this.workout});

  @override
  Widget build(BuildContext context) {
    final minutes = workout.duration.inMinutes;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  workout.title,
                  style: AppTextStyles.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatHevyWorkoutDate(workout.startTime)} · $minutes min',
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            '${workout.exerciseCount} exercises\n${workout.setCount} sets',
            textAlign: TextAlign.right,
            style: AppTextStyles.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _EmptyWorkouts extends StatelessWidget {
  const _EmptyWorkouts();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Column(
          children: [
            Icon(
              Icons.fitness_center_outlined,
              color: AppColors.textMuted,
              size: 36,
            ),
            SizedBox(height: AppSpace.md),
            Text('No imported workouts yet.', style: AppTextStyles.bodyMedium),
            SizedBox(height: AppSpace.xs),
            Text(
              'Connect Hevy and run a sync to see your workouts here.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
}

String formatHevyWorkoutDate(DateTime value) {
  final date = value.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
