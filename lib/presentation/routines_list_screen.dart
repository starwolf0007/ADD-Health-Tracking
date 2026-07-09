// lib/presentation/routines_list_screen.dart
//
// The Routines tab. A quiet list of active routines.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/presentation/routine_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

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
        error: (e, _) => const Center(child: Text('Error loading routines')),
        data: (routines) {
          if (routines.isEmpty) {
            return const Center(child: Text('No routines yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpace.xl),
            itemCount: routines.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md),
            itemBuilder: (context, i) => _RoutineCard(routine: routines[i]),
          );
        },
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  final Routine routine;
  const _RoutineCard({required this.routine});

  String get _timeLabel {
    switch (routine.anchor) {
      case RoutineAnchor.morning: return 'Morning';
      case RoutineAnchor.midday: return 'Midday';
      case RoutineAnchor.evening: return 'Evening';
      case RoutineAnchor.custom:
        final h = routine.scheduleHour ?? 0;
        final m = routine.scheduleMinute ?? 0;
        final mm = m.toString().padLeft(2, '0');
        final period = h >= 12 ? 'PM' : 'AM';
        final h12 = h % 12 == 0 ? 12 : h % 12;
        return '$h12:$mm $period';
    }
  }

  String? get _daysLabel {
    final d = routine.activeDays;
    if (d == null || d.isEmpty || d.length == 7) return null;
    if (d == '12345') return 'Weekdays';
    if (d == '67') return 'Weekends';
    return d.split('').join(',');
  }

  @override
  Widget build(BuildContext context) {
    final done = routine.completedCount;
    final total = routine.steps.length;
    
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
                    Text(
                      _daysLabel == null ? _timeLabel : '$_timeLabel · $_daysLabel',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              Text('$done/$total', style: AppTextStyles.monoSmall),
              const SizedBox(width: AppSpace.sm),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
