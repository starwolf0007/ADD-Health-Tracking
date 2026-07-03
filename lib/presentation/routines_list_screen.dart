// lib/presentation/routines_list_screen.dart
//
// The Routines tab (v2). A quiet list: name, anchor time, progress.
// Tap launches the existing one-step-at-a-time RoutineScreen runner —
// this screen adds zero new mechanics, just a front door.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/routine.dart';
import 'routine_screen.dart';
import 'theme.dart';
class RoutinesListScreen extends ConsumerWidget {
  const RoutinesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(activeRoutinesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        centerTitle: false,
      ),
      body: routinesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (e, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Text('Routines are unavailable right now.',
                style: AppTextStyles.bodyMedium),
          ),
        ),
        data: (routines) {
          if (routines.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpace.xl),
                child: Text(
                  'No routines yet.\nThe morning and wind-down seeds arrive '
                  'on first launch.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xxl),
            itemCount: routines.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpace.md),
            itemBuilder: (context, i) =>
                _RoutineCard(routine: routines[i]),
          );
        },
      ),
    );
  }
}

class _RoutineCard extends ConsumerWidget {
  final Routine routine;

  const _RoutineCard({required this.routine});

  String get _timeLabel {
    // Named anchors describe their own window; custom shows the set time.
    switch (routine.anchor) {
      case RoutineAnchor.morning:
        return 'Morning';
      case RoutineAnchor.midday:
        return 'Midday';
      case RoutineAnchor.evening:
        return 'Evening';
      case RoutineAnchor.custom:
        final h = routine.scheduleHour;
        final m = routine.scheduleMinute;
        if (h == null) return 'Custom';
        final mm = (m ?? 0).toString().padLeft(2, '0');
        final period = h >= 12 ? 'PM' : 'AM';
        final h12 = h % 12 == 0 ? 12 : h % 12;
        return '$h12:$mm $period';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = routine.steps.length;
    final done = routine.completedCount;
    final complete = total > 0 && done >= total;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        onTap: () => launchRoutine(context, routine),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.name, style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppSpace.xs),
                    Text(_timeLabel, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Text(
                complete ? 'done' : '$done/$total',
                style: AppTextStyles.monoSmall.copyWith(
                  color: complete
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
