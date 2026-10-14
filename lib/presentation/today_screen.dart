import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/domain/date_key.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/presentation/lexi_conversation_screen.dart';
import 'package:neuroflow/presentation/settings_screen.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today/lexi_avatar.dart';
import 'package:neuroflow/executive/planner.dart';
import 'package:neuroflow/executive/timeline_logic.dart';
import 'package:neuroflow/presentation/widgets/capture_sheet.dart';
import 'package:neuroflow/presentation/widgets/due_routines_card.dart';

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
    final selectedDay = ref.watch(selectedDayProvider);
    final currentDay = ref.watch(currentDayProvider);
    final isViewingToday = isSameDay(selectedDay, currentDay);
    ref.watch(todayControllerProvider);
    final realNow = widget.now ?? DateTime.now();
    final phaseNow = isViewingToday
        ? realNow
        : selectedDay.isBefore(currentDay)
            ? DateTime(selectedDay.year, selectedDay.month, selectedDay.day + 1)
            : selectedDay;
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
            key: ValueKey(
              'today-body-${dateOnly(selectedDay).toIso8601String()}',
            ),
            data: data,
            now: phaseNow,
            viewedDay: selectedDay,
            isViewingToday: isViewingToday,
            scrollController: _scrollController,
            currentKey: _currentKey,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add task',
        onPressed: () => showCaptureSheet(
          context,
          scheduledDay: isViewingToday ? null : selectedDay,
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

bool _quickWinsActive(TodayState? state, {required bool isViewingToday}) =>
    isViewingToday &&
    state != null &&
    state.mode == DayMode.quickWins &&
    state.quickWins.isNotEmpty;

class _TodayTimelineBody extends ConsumerWidget {
  final TodayTimelineData data;
  final DateTime now;
  final DateTime viewedDay;
  final bool isViewingToday;
  final ScrollController scrollController;
  final GlobalKey currentKey;

  const _TodayTimelineBody({
    super.key,
    required this.data,
    required this.now,
    required this.viewedDay,
    required this.isViewingToday,
    required this.scrollController,
    required this.currentKey,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommended = data.recommendedTask;
    final dayItems = data.items
        .where((item) => item.type != TimelineItemType.flexibleBlock)
        .toList();
    final flexibleItems = data.items
        .where((item) => item.type == TimelineItemType.flexibleBlock)
        .toList();
    final markerIndex = dayItems.indexWhere(
      (item) => item.phaseAt(now) != TimelinePhase.past,
    );

    final todayState = ref.watch(todayControllerProvider).value;
    final isQuickWins =
        _quickWinsActive(todayState, isViewingToday: isViewingToday);
    final quickWinTasks = isQuickWins ? todayState!.quickWins : const <Task>[];

    final fixedItems = [
      for (final item in dayItems)
        if (item.type == TimelineItemType.fixedAnchor ||
            item.type == TimelineItemType.calendarEvent)
          item,
    ];

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(todayControllerProvider);
        ref.invalidate(dueRoutinesProvider);
        await ref.refresh(todayTimelineProvider.future);
      },
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          MediaQuery.of(context).viewPadding.bottom + 72,
        ),
        children: [
          _DateNavigator(
            selectedDay: viewedDay,
            isViewingToday: isViewingToday,
          ),
          const SizedBox(height: AppSpace.md),
          _DaySummaryCard(
            data: data,
            reason: isViewingToday ? todayState?.reason ?? '' : '',
          ),
          if (!data.hasCalendarPermission) ...[
            const SizedBox(height: AppSpace.md),
            const _CalendarPermissionNotice(),
          ],
          if (isViewingToday) ...[
            const SizedBox(height: AppSpace.md),
            const DueRoutinesCard(),
          ],
          if (isQuickWins) ...[
            const SizedBox(height: AppSpace.lg),
            _QuickWinsCard(tasks: quickWinTasks),
            if (fixedItems.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xl),
              const Text('Still fixed today', style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpace.md),
              for (final item in fixedItems) _TimelineRow(item: item, now: now),
            ],
          ] else ...[
            if (recommended != null) ...[
              const SizedBox(height: AppSpace.lg),
              _ActiveTaskCard(task: recommended),
            ],
            const SizedBox(height: AppSpace.xl),
            Text(
              isViewingToday ? 'Your day' : 'Schedule for this day',
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: AppSpace.md),
            if (data.items.isEmpty)
              const _EmptyDayState()
            else ...[
              if (dayItems.isEmpty)
                const Text('Nothing scheduled yet.',
                    style: AppTextStyles.bodySmall),
              for (var index = 0; index < dayItems.length; index++) ...[
                if (index == markerIndex)
                  _CurrentTimeMarker(key: currentKey, now: now),
                _TimelineRow(item: dayItems[index], now: now),
              ],
              if (markerIndex == -1 && dayItems.isNotEmpty)
                _CurrentTimeMarker(key: currentKey, now: now),
            ],
            if (flexibleItems.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xl),
              const Text('Flexible tasks', style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpace.md),
              for (final item in flexibleItems)
                _TimelineRow(item: item, now: now),
            ],
          ],
        ],
      ),
    );
  }
}

class _QuickWinsCard extends StatelessWidget {
  final List<Task> tasks;

  const _QuickWinsCard({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('quick-wins-card'),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.accentWash,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text('Quick Wins',
                    style:
                        AppTextStyles.label.copyWith(color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          const Text(
            'A lighter shape for today. Tap a win to mark it done. '
            'Nothing else is tracked today.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < tasks.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpace.sm),
            _QuickWinRow(task: tasks[i]),
          ],
        ],
      ),
    );
  }
}

class _QuickWinRow extends ConsumerWidget {
  final Task task;

  const _QuickWinRow({required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      container: true,
      button: true,
      label: 'Quick win, ${task.title}, tap when done',
      child: Material(
        color: AppColors.surfaceGlass,
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        child: InkWell(
          key: ValueKey('quick-win-${task.id}'),
          borderRadius: BorderRadius.circular(AppSpace.radiusInput),
          onTap: () => _complete(context, ref),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.md,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpace.radiusInput),
              border: Border.all(
                color: AppColors.divider,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(task.title,
                      style: AppTextStyles.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    unawaited(HapticFeedback.lightImpact());
    try {
      await ref.read(taskActionControllerProvider).complete(task.id);
    } on TaskActionFailure catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not ${error.action}. Try again.')),
      );
    }
  }
}

class _DateNavigator extends ConsumerWidget {
  final DateTime selectedDay;
  final bool isViewingToday;

  const _DateNavigator({
    required this.selectedDay,
    required this.isViewingToday,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localizations = MaterialLocalizations.of(context);
    final dateLabel = isViewingToday
        ? 'Today · ${localizations.formatFullDate(selectedDay)}'
        : '${_relativeLabel()} · ${localizations.formatFullDate(selectedDay)}';
    final selected = ref.read(selectedDayProvider.notifier);
    return Semantics(
      label: 'Date navigation, $dateLabel',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
        decoration: BoxDecoration(
          color: AppColors.surfaceGlass,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('date-previous-day'),
              tooltip: 'Previous day',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: selected.previousDay,
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppSpace.radiusInput),
                onTap: () async {
                  final day = await showDatePicker(
                    context: context,
                    initialDate: selectedDay,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (day != null) selected.select(day);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  child: Text(
                    dateLabel,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('date-next-day'),
              tooltip: 'Next day',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: selected.nextDay,
            ),
            if (!isViewingToday)
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.xs),
                child: TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: selected.goToToday,
                  child: const Text('Back to Today'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _relativeLabel() {
    final now = dateOnly(DateTime.now());
    if (isSameDay(selectedDay, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    if (isSameDay(selectedDay, now.add(const Duration(days: 1)))) {
      return 'Tomorrow';
    }
    return 'Selected day';
  }
}

class _DaySummaryCard extends ConsumerWidget {
  final TodayTimelineData data;
  final String reason;

  const _DaySummaryCard({required this.data, required this.reason});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: 'Open Lexi conversation',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        onTap: () {
          if (data.lexiAvailable) {
            unawaited(
              ref
                  .read(todayControllerProvider.notifier)
                  .requestLexiRefinement(),
            );
          }
          Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const LexiConversationScreen(),
          ));
        },
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.surfaceGlass,
            borderRadius: BorderRadius.circular(AppSpace.radiusCard),
            border: Border.all(color: AppColors.divider),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 18,
                  offset: Offset(0, 8)),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const LexiAvatar(
                visualState: LexiVisualState.idle,
                assetPath: 'assets/lexi/public/lexi-canonical-face.jpg',
                size: 44,
                subtleIdleAnimation: true,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                              data.lexiAvailable
                                  ? 'A calm look ahead'
                                  : 'Your plan, on device',
                              style: AppTextStyles.label
                                  .copyWith(color: AppColors.accent)),
                        ),
                        Text(
                          data.lexiAvailable
                              ? 'Tap to talk with Lexi'
                              : 'Lexi is offline. Everything here still works.',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(const DaySummary().build(data),
                        style: AppTextStyles.bodyMedium),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        reason,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.accent),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.xs),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        border: Border.all(
          color: isActive ? AppColors.accent : AppColors.divider,
          width: isActive ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
         mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: item.isCompleted
                                    ? AppTextStyles.bodySmall.copyWith(
                                        decoration: TextDecoration.lineThrough,
                                      )
                                    : AppTextStyles.bodyMedium,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (item.isPaused)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.warning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Paused',
                                    style: AppTextStyles.label
                                        .copyWith(color: AppColors.warning)),
                              ),
                            if (item.task != null) ...[
                              IconButton(
                                key: ValueKey(
                                    'timeline-task-edit-${item.task!.id}'),
                                tooltip: 'Edit timeline item',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                color: AppColors.textMuted,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editTask(context),
                              ),
                              IconButton(
                                key: ValueKey(
                                    'timeline-task-delete-${item.task!.id}'),
                                tooltip: 'Delete task',
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                color: AppColors.textMuted,
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _deleteTask(context, ref),
                              ),
                            ],
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
                            item.subtitle?.isNotEmpty == true) ...[
                          const SizedBox(height: 2),
                          Text(item.subtitle!,
                              style: AppTextStyles.bodySmall, maxLines: 2),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
                width: 56,
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
