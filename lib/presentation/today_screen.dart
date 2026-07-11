import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/presentation/lexi_conversation_screen.dart';
import 'package:neuroflow/presentation/settings_screen.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today/lexi_avatar.dart';
import 'package:neuroflow/presentation/today/today_timeline.dart';
import 'package:neuroflow/presentation/widgets/capture_sheet.dart';

class TodayScreen extends ConsumerStatefulWidget {
  final DateTime? now;
  const TodayScreen({super.key, this.now});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final _scrollController = ScrollController();
  final _currentKey = GlobalKey();
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollNearNow() {
    if (_didInitialScroll) return;
    _didInitialScroll = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _currentKey.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(context,
            alignment: .38, duration: const Duration(milliseconds: 350));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(todayTimelineProvider);
    final name = ref.watch(displayNameProvider).value ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Today' : 'Hey, $name'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: timeline.when(
        loading: () => const _LoadingState(),
        error: (error, _) => _ErrorState(
          onRetry: () => ref.invalidate(todayTimelineProvider),
        ),
        data: (data) {
          _scrollNearNow();
          return _TodayTimelineBody(
            data: data,
            now: widget.now ?? DateTime.now(),
            scrollController: _scrollController,
            currentKey: _currentKey,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => showCaptureSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _TodayTimelineBody extends ConsumerWidget {
  final TodayTimelineData data;
  final DateTime now;
  final ScrollController scrollController;
  final GlobalKey currentKey;

  const _TodayTimelineBody({
    required this.data,
    required this.now,
    required this.scrollController,
    required this.currentKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommended = data.recommendedTask;
    final markerIndex = data.items.indexWhere(
      (item) => item.phaseAt(now) != TimelinePhase.past,
    );
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(todayTimelineProvider.future),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          MediaQuery.of(context).viewPadding.bottom + 72,
        ),
        children: [
          _DaySummaryCard(data: data),
          if (!data.hasCalendarPermission) ...[
            const SizedBox(height: AppSpace.md),
            const _CalendarPermissionNotice(),
          ],
          if (recommended != null) ...[
            const SizedBox(height: AppSpace.lg),
            _ActiveTaskCard(task: recommended),
          ],
          const SizedBox(height: AppSpace.xl),
          const Text('Your day', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpace.md),
          if (data.items.isEmpty)
            const _EmptyDayState()
          else ...[
            for (var index = 0; index < data.items.length; index++) ...[
              if (index == markerIndex)
                _CurrentTimeMarker(key: currentKey, now: now),
              _TimelineRow(item: data.items[index], now: now),
            ],
            if (markerIndex == -1)
              _CurrentTimeMarker(key: currentKey, now: now),
          ],
        ],
      ),
    );
  }
}

class _DaySummaryCard extends StatelessWidget {
  final TodayTimelineData data;
  const _DaySummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Open Lexi conversation',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const LexiConversationScreen(),
        )),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceGlass,
            borderRadius: BorderRadius.circular(AppSpace.radiusCard),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 18,
                  offset: Offset(0, 8)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LexiAvatar(
                visualState: LexiVisualState.idle,
                assetPath: 'assets/lexi/public/lexi-canonical-face.jpg',
                size: 48,
                subtleIdleAnimation: true,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        data.lexiAvailable
                            ? 'A calm look ahead'
                            : 'Your plan, on device',
                        style: AppTextStyles.label
                            .copyWith(color: AppColors.accent)),
                    const SizedBox(height: AppSpace.sm),
                    Text(const DaySummary().build(data),
                        style: AppTextStyles.bodyMedium),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      data.lexiAvailable
                          ? 'Tap to talk with Lexi'
                          : 'Lexi is offline. Everything here still works.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveTaskCard extends ConsumerWidget {
  final Task task;
  const _ActiveTaskCard({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.read(taskActionControllerProvider);
    final isPaused = task.status == TaskStatus.paused;
    final isActive = task.status == TaskStatus.inProgress;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              LexiAvatar(
                visualState: LexiVisualState.focus,
                assetPath: 'assets/lexi/public/lexi-canonical-face.jpg',
                size: 30,
              ),
              SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text('Recommended now', style: AppTextStyles.label),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(task.title, style: AppTextStyles.titleMedium),
          if (task.notes?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpace.xs),
            Text(task.notes!, style: AppTextStyles.bodySmall),
          ],
          const SizedBox(height: AppSpace.lg),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              FilledButton.icon(
                onPressed: () =>
                    isPaused ? actions.resume(task.id) : actions.start(task.id),
                icon: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.flag_outlined),
                label: Text(isPaused
                    ? 'Resume'
                    : isActive
                        ? 'Continue'
                        : 'Start'),
              ),
              OutlinedButton(
                onPressed: () => _saveForLater(context, ref),
                child: const Text('Save for later'),
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

  Future<void> _saveForLater(BuildContext context, WidgetRef ref) async {
    final last = TextEditingController();
    final next = TextEditingController();
    DateTime? returnAt;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Save for later'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'A note can make returning easier, but every field is optional.',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: last,
                    decoration: const InputDecoration(
                      labelText: 'Last completed step (Optional)',
                    ),
                  ),
                  TextField(
                    controller: next,
                    decoration: const InputDecoration(
                      labelText: 'Exact next action (Optional)',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: const Text('Return time (Optional)'),
                    subtitle: Text(returnAt == null
                        ? 'No return time'
                        : '${returnAt!.month}/${returnAt!.day}  ${_time(returnAt)}'),
                    onTap: () async {
                      final picked = await _pickReturnTime(context);
                      if (picked != null) {
                        setDialogState(() => returnAt = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save and pause'),
              ),
            ],
          ),
        ),
      );
      if (saved != true) return;

      final lastStep = last.text.trim();
      final nextAction = next.text.trim();
      final hasNote =
          lastStep.isNotEmpty || nextAction.isNotEmpty || returnAt != null;
      await ref.read(taskActionControllerProvider).saveForLater(
            task.id,
            hasNote
                ? ReentryNote(
                    lastCompletedStep: lastStep.isEmpty ? null : lastStep,
                    nextAction: nextAction.isEmpty ? null : nextAction,
                    returnAt: returnAt,
                    updatedAt: DateTime.now(),
                  )
                : null,
          );
    } finally {
      last.dispose();
      next.dispose();
    }
  }

  Future<DateTime?> _pickReturnTime(BuildContext context) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}

class _TimelineRow extends StatelessWidget {
  final TimelineItem item;
  final DateTime now;
  const _TimelineRow({required this.item, required this.now});

  @override
  Widget build(BuildContext context) {
    final phase = item.phaseAt(now);
    final dimmed = phase == TimelinePhase.past;
    final icon = switch (item.type) {
      TimelineItemType.calendarEvent => Icons.event_outlined,
      TimelineItemType.fixedAnchor => Icons.anchor_rounded,
      TimelineItemType.flexibleBlock => Icons.drag_indicator_rounded,
      TimelineItemType.task => Icons.check_box_outline_blank_rounded,
      TimelineItemType.openSpace => Icons.air_rounded,
    };
    // Muted type colors are a secondary signal only. Icon, marker geometry,
    // visible type label, and semantics keep every type distinct in grayscale.
    final color = switch (item.type) {
      TimelineItemType.calendarEvent => AppColors.calendar,
      TimelineItemType.fixedAnchor => AppColors.accent,
      TimelineItemType.flexibleBlock => AppColors.textSecondary,
      TimelineItemType.task => AppColors.textPrimary,
      TimelineItemType.openSpace => AppColors.textMuted,
    };
    final typeLabel = _timelineTypeLabel(item.type);
    return Semantics(
      container: true,
      label: '$typeLabel, ${item.title}, ${_phaseLabel(phase)}'
          '${item.isPaused ? ', paused' : ''}',
      child: Opacity(
        opacity: dimmed ? .55 : 1,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: item.isCompleted ? 4 : 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Text(_time(item.start), style: AppTextStyles.monoSmall),
              ),
              Column(
                children: [
                  Container(width: 2, height: 8, color: AppColors.divider),
                  _TimelineMarker(
                    type: item.type,
                    icon: item.isCompleted ? Icons.check_rounded : icon,
                    color: color,
                    completed: item.isCompleted,
                  ),
                  Container(
                      width: 2,
                      height: item.isCompleted ? 20 : 46,
                      color: AppColors.divider),
                ],
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(item.title,
                                style: item.isCompleted
                                    ? AppTextStyles.bodySmall
                                    : AppTextStyles.bodyMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                          if (item.isPaused)
                            Text('Paused',
                                style: AppTextStyles.label
                                    .copyWith(color: AppColors.warning)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        typeLabel.toUpperCase(),
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                        ),
                      ),
                      if (!item.isCompleted &&
                          item.subtitle?.isNotEmpty == true)
                        Text(item.subtitle!,
                            style: AppTextStyles.bodySmall, maxLines: 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelineMarker extends StatelessWidget {
  final TimelineItemType type;
  final IconData icon;
  final Color color;
  final bool completed;

  const _TimelineMarker({
    required this.type,
    required this.icon,
    required this.color,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = switch (type) {
      TimelineItemType.fixedAnchor => BorderRadius.circular(2),
      TimelineItemType.calendarEvent => BorderRadius.circular(6),
      TimelineItemType.flexibleBlock => BorderRadius.circular(3),
      TimelineItemType.task => BorderRadius.circular(12),
      TimelineItemType.openSpace => BorderRadius.circular(12),
    };
    final marker = Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: completed ? AppColors.accentWash : Colors.transparent,
        borderRadius: borderRadius,
        border: Border.all(
          color: color,
          width: type == TimelineItemType.flexibleBlock ? 1 : 1.5,
        ),
      ),
      child: Icon(icon, color: color, size: 14),
    );
    return type == TimelineItemType.fixedAnchor
        ? Transform.rotate(angle: .785398, child: marker)
        : marker;
  }
}

class _CurrentTimeMarker extends StatelessWidget {
  final DateTime now;
  const _CurrentTimeMarker({super.key, required this.now});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Current time ${_time(now)}',
      child: Row(
        children: [
          SizedBox(
              width: 54,
              child: Text(_time(now),
                  style: AppTextStyles.monoSmall
                      .copyWith(color: AppColors.accent))),
          const CircleAvatar(radius: 5, backgroundColor: AppColors.accent),
          const SizedBox(width: 6),
          const Expanded(child: Divider(color: AppColors.accent)),
          const SizedBox(width: 6),
          Text('NOW',
              style: AppTextStyles.label.copyWith(color: AppColors.accent)),
        ],
      ),
    );
  }
}

class _CalendarPermissionNotice extends StatelessWidget {
  const _CalendarPermissionNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.accentWash,
          borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        ),
        child: const Row(
          children: [
            Icon(Icons.event_busy_outlined, color: AppColors.textSecondary),
            SizedBox(width: AppSpace.sm),
            Expanded(
                child: Text(
                    'Calendar is not connected. Tasks and anchors are still shown.',
                    style: AppTextStyles.bodySmall)),
          ],
        ),
      );
}

class _EmptyDayState extends StatelessWidget {
  const _EmptyDayState();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.wb_twilight_outlined,
                  size: 46, color: AppColors.accent),
              SizedBox(height: AppSpace.lg),
              Text('Your day has room', style: AppTextStyles.titleMedium),
              SizedBox(height: AppSpace.sm),
              Text('Add one next step, or leave the space open.',
                  style: AppTextStyles.bodySmall),
            ],
          ),
        ),
      );
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) => const Center(
        child:
            CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
      );
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, color: AppColors.warning),
              const SizedBox(height: AppSpace.md),
              const Text('Today could not be loaded',
                  style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpace.sm),
              const Text(
                  'Your data is still on this device. Try again when you are ready.',
                  style: AppTextStyles.bodySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.lg),
              OutlinedButton(
                  onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

String _time(DateTime? value) {
  if (value == null) return '';
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour < 12 ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

String _timelineTypeLabel(TimelineItemType type) => switch (type) {
      TimelineItemType.calendarEvent => 'Calendar event',
      TimelineItemType.fixedAnchor => 'Fixed anchor',
      TimelineItemType.flexibleBlock => 'Flexible block',
      TimelineItemType.task => 'Task',
      TimelineItemType.openSpace => 'Open time',
    };

String _phaseLabel(TimelinePhase phase) => switch (phase) {
      TimelinePhase.past => 'past',
      TimelinePhase.current => 'current',
      TimelinePhase.upcoming => 'upcoming',
    };
