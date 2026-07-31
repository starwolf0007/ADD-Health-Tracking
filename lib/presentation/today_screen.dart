import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
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
    // Watch the Quick Wins decision at the screen level (not only inside the
    // body): the body is built lazily inside timeline.when(data:), so relying
    // on its watch alone lets the controller start resolving a frame late and
    // the reduced view lag behind the timeline. Watching here keeps it eager
    // and rebuilds Today when the mode flips.
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
            // Fresh subtree per viewed day. Quick Wins entry/exit is the
            // Executive's decision (read inside the body), not view state —
            // there is no per-session disclosure to preserve or reset.
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

/// Single definition of Quick Wins activation.
///
/// Both the reduced view in [_TodayTimelineBody] and the reset key in
/// [_TodayScreenState] read this, so the two can never disagree about whether
/// the mode is on. Scoped to the day the mood signal is about: browsing
/// another day always shows that day's real schedule.
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

    // Quick Wins reshape (#37). Entry AND exit are the Executive's job, driven
    // by the mood signal; Presentation only reads the decision. Per the LOCKED
    // v1.3 spec (§158/§170) there is no manual toggle and no user action to
    // enter, leave, or maintain the reduced state.
    final todayState = ref.watch(todayControllerProvider).value;
    final isQuickWins =
        _quickWinsActive(todayState, isViewingToday: isViewingToday);
    final quickWinTasks =
        isQuickWins ? todayState!.quickWins : const <Task>[];

    // Commitments stay visible even in the reduced view. Hiding a real shift
    // or appointment would make a calm screen a dishonest one.
    final fixedItems = [
      for (final item in dayItems)
        if (item.type == TimelineItemType.fixedAnchor ||
            item.type == TimelineItemType.calendarEvent)
          item,
    ];

    return RefreshIndicator(
      // Quick Wins mode comes from todayControllerProvider, so refreshing only
      // the timeline could leave a stale reduction (or a stale full day) on
      // screen. Pull-to-refresh means "re-derive this screen".
      onRefresh: () async {
        ref.invalidate(todayControllerProvider);
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
          _DaySummaryCard(data: data),
          if (!data.hasCalendarPermission) ...[
            const SizedBox(height: AppSpace.md),
            const _CalendarPermissionNotice(),
          ],
          if (isQuickWins) ...[
            // Reduced Quick Wins state: the capped list, real commitments, and
            // the permission-to-stop label — and nothing else. No full-day
            // access; exit is automatic when the signal lifts (§158/§170).
            const SizedBox(height: AppSpace.lg),
            _QuickWinsCard(tasks: quickWinTasks),
            if (fixedItems.isNotEmpty) ...[
              const SizedBox(height: AppSpace.xl),
              const Text('Still fixed today', style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpace.md),
              for (final item in fixedItems)
                _TimelineRow(item: item, now: now),
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

/// The Quick Wins surface (#37): at most three low-effort options, already
/// selected and capped by the Executive.
///
/// Deliberately carries no count, score, or progress figure — §13 forbids
/// visible numeric self-judgment, and the short list is the whole message.
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LexiAvatar(
                visualState: LexiVisualState.idle,
                assetPath: 'assets/lexi/public/lexi-canonical-face.jpg',
                size: 30,
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
          for (final task in tasks) _QuickWinRow(task: task),
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
      child: InkWell(
        key: ValueKey('quick-win-${task.id}'),
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        onTap: () => _complete(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Row(
            children: [
              const Icon(
                Icons.check_box_outline_blank_rounded,
                size: 18,
                color: AppColors.textSecondary,
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
    );
  }

  // §167: a Quick Win is one-tap *done*. Completing removes it from the
  // pending pool, so the Executive re-derives and the capped list refills
  // with the next low-effort candidate. There is no "start"/timer step here —
  // the point is momentum, not task management.
  Future<void> _complete(BuildContext context, WidgetRef ref) async {
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
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('date-previous-day'),
            tooltip: 'Previous day',
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
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('date-next-day'),
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: selected.nextDay,
          ),
          if (!isViewingToday)
            TextButton(
              onPressed: selected.goToToday,
              child: const Text('Back to Today'),
            ),
        ],
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
  const _DaySummaryCard({required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reason = ref.watch(todayControllerProvider).value?.reason ?? '';
    return Semantics(
      button: true,
      label: 'Open Lexi conversation',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        onTap: () {
          // Explicit, user-initiated trigger for TodayController's opt-in
          // Lexi refinement (ADR-001) — never called automatically. Tapping
          // this card to open Lexi is the one intended explicit action.
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
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        reason,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.accent),
                      ),
                    ],
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
          if (isActive && task.activeStartedAt != null) ...[
            const SizedBox(height: AppSpace.sm),
            _ActiveTaskTimer(startedAt: task.activeStartedAt!),
          ],
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
                onPressed: isActive
                    ? null
                    : () async {
                        try {
                          if (isPaused) {
                            await actions.resume(task.id);
                          } else {
                            await actions.start(task.id);
                          }
                          if (!context.mounted) return;
                          unawaited(_showTimerPermissionHint(context, ref));
                        } on TaskActionFailure catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content:
                                  Text('Could not ${error.action}. Try again.'),
                            ),
                          );
                        }
                      },
                icon: Icon(
                    isPaused ? Icons.play_arrow_rounded : Icons.flag_outlined),
                label: Text(isPaused
                    ? 'Resume'
                    : isActive
                        ? 'Running'
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
      try {
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
      } on TaskActionFailure catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not ${error.action}. Try again.'),
          ),
        );
      }
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

  Future<void> _showTimerPermissionHint(
      BuildContext context, WidgetRef ref) async {
    final notifications = ref.read(notificationServiceProvider);
    final enabled = await notifications.areNotificationsEnabled();
    if (enabled != false || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
            'Allow notifications to see the task timer outside the app.'),
        action: SnackBarAction(
          label: 'Allow',
          onPressed: () => unawaited(
            notifications.requestNotificationPermission(),
          ),
        ),
      ),
    );
  }
}

class _ActiveTaskTimer extends StatelessWidget {
  final DateTime startedAt;

  const _ActiveTaskTimer({required this.startedAt});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (tick) => tick),
      builder: (context, _) {
        final elapsed = DateTime.now().difference(startedAt);
        final safeElapsed = elapsed.isNegative ? Duration.zero : elapsed;
        final hours = safeElapsed.inHours;
        final minutes = safeElapsed.inMinutes.remainder(60);
        final seconds = safeElapsed.inSeconds.remainder(60);
        final value = hours > 0
            ? '${hours.toString().padLeft(2, '0')}:'
                '${minutes.toString().padLeft(2, '0')}:'
                '${seconds.toString().padLeft(2, '0')}'
            : '${minutes.toString().padLeft(2, '0')}:'
                '${seconds.toString().padLeft(2, '0')}';
        return Semantics(
          liveRegion: true,
          label: 'Task running for $value',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.timer_outlined,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: AppSpace.xs),
              Text(value,
                  key: const ValueKey('active-task-timer'),
                  style: AppTextStyles.label.copyWith(
                    color: AppColors.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        );
      },
    );
  }
}

class _TimelineRow extends ConsumerWidget {
  final TimelineItem item;
  final DateTime now;
  const _TimelineRow({required this.item, required this.now});

  Future<void> _editTask(BuildContext context) async {
    final task = item.task;
    if (task == null) return;
    await showTaskEditSheet(context, task);
  }

  Future<void> _deleteTask(BuildContext context, WidgetRef ref) async {
    final task = item.task;
    if (task == null) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('Delete “${task.title}” from your timeline?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    try {
      if (task.status == TaskStatus.inProgress) {
        await ref.read(taskActionControllerProvider).pause(task.id);
      }
      await ref.read(taskRepositoryProvider).delete(task.id);
      ref.invalidate(todayControllerProvider);
      ref.invalidate(todayTimelineProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task deleted')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete task. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      button: item.task != null && !item.isCompleted,
      label: '$typeLabel, ${item.title}, ${_phaseLabel(phase)}'
          '${item.isPaused ? ', paused' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusInput),
        onTap: item.task == null || item.isCompleted
            ? null
            : () async {
                final task = item.task!;
                if (task.status == TaskStatus.inProgress) return;
                try {
                  final actions = ref.read(taskActionControllerProvider);
                  if (task.status == TaskStatus.paused) {
                    await actions.resume(task.id);
                  } else {
                    await actions.start(task.id);
                  }
                } on TaskActionFailure catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not ${error.action}. Try again.'),
                    ),
                  );
                }
              },
        child: Opacity(
          opacity: dimmed ? .55 : 1,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: item.isCompleted ? 4 : 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 54,
                  child:
                      Text(_time(item.start), style: AppTextStyles.monoSmall),
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
                            if (item.task != null) ...[
                              IconButton(
                                key: ValueKey(
                                    'timeline-task-edit-${item.task!.id}'),
                                tooltip: 'Edit timeline item',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _editTask(context),
                              ),
                              IconButton(
                                key: ValueKey(
                                    'timeline-task-delete-${item.task!.id}'),
                                tooltip: 'Delete task',
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
