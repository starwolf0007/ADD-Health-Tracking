// lib/presentation/timeline_screen.dart
//
// PHASE 2 · STEP 2 — the read-only "Your Day" timeline projection.
// A ListView of the merged TimelineEvent list assembled from the typed
// tables. This screen reads timelineProvider ONLY. It never writes.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/timeline.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/widgets/re_entry_card.dart';

class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(timelineProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Your Day'), centerTitle: false),
      body: Column(
        children: [
          const ReEntryCard(),
          Expanded(
            child: events.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpace.xl),
                      child: Text(
                        'Your day builds itself here.\nComplete a task, log a mood, '
                        'run a routine — it all lands on one spine.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                        AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.xxl),
                    itemCount: events.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpace.md),
                    itemBuilder: (context, i) => _EventRow(event: events[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final TimelineEvent event;

  const _EventRow({required this.event});

  ({IconData icon, Color color}) get _visual => switch (event.kind) {
        TimelineEventKind.taskCompleted => (
            icon: Icons.check_circle,
            color: AppColors.accent
          ),
        TimelineEventKind.taskPaused => (
            icon: Icons.pause_circle_outline,
            color: AppColors.attention
          ),
        TimelineEventKind.taskBlocked => (
            icon: Icons.block,
            color: AppColors.attention
          ),
        TimelineEventKind.taskCheckpoint => (
            icon: Icons.flag_outlined,
            color: AppColors.accent
          ),
        TimelineEventKind.routineDue => (
            icon: Icons.repeat_rounded,
            color: AppColors.textSecondary
          ),
        TimelineEventKind.moodLogged => (
            icon: Icons.spa_outlined,
            color: AppColors.accent
          ),
      };

  String get _time {
    final h = event.timestamp.hour;
    final m = event.timestamp.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $period';
  }

  @override
  Widget build(BuildContext context) {
    final v = _visual;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(_time,
              style: AppTextStyles.monoSmall
                  .copyWith(color: AppColors.textMuted)),
        ),
        Icon(v.icon, size: 18, color: v.color),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(event.title, style: AppTextStyles.bodyMedium),
              if (event.subtitle != null)
                Text(event.subtitle!, style: AppTextStyles.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
