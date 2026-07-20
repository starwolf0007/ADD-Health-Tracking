// lib/executive/timeline_logic.dart
//
// Today timeline construction and day-summary rules. Pure Dart — no Flutter,
// no Drift, no Google — depends only on domain.

import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/domain/task.dart';

enum TimelineItemType {
  calendarEvent,
  fixedAnchor,
  flexibleBlock,
  task,
  openSpace,
}

enum TimelinePhase { past, current, upcoming }

class TimelineItem {
  final String id;
  final TimelineItemType type;
  final String title;
  final String? subtitle;
  final DateTime? start;
  final DateTime? end;
  final Task? task;
  final bool isCompleted;
  final bool isPaused;

  const TimelineItem({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.start,
    this.end,
    this.task,
    this.isCompleted = false,
    this.isPaused = false,
  });

  TimelinePhase phaseAt(DateTime now) {
    if (isCompleted || (end != null && !end!.isAfter(now))) {
      return TimelinePhase.past;
    }
    if (start != null &&
        !start!.isAfter(now) &&
        (end == null || end!.isAfter(now))) {
      return TimelinePhase.current;
    }
    return TimelinePhase.upcoming;
  }
}

abstract class TodayCalendarSource {
  const TodayCalendarSource();
  bool get hasPermission;
  Future<List<TimelineItem>> load(DateTime day);
}

class NoCalendarSource extends TodayCalendarSource {
  const NoCalendarSource();

  @override
  bool get hasPermission => false;

  @override
  Future<List<TimelineItem>> load(DateTime day) async => const [];
}

class TodayTimelineData {
  final List<TimelineItem> items;
  final Task? recommendedTask;
  final bool hasCalendarPermission;
  final bool lexiAvailable;

  const TodayTimelineData({
    required this.items,
    required this.recommendedTask,
    required this.hasCalendarPermission,
    required this.lexiAvailable,
  });
}

class TodayTimelineBuilder {
  const TodayTimelineBuilder();

  List<TimelineItem> build({
    required DateTime day,
    required List<Task> tasks,
    required List<Routine> routines,
    List<TimelineItem> calendarItems = const [],
  }) {
    final items = <TimelineItem>[...calendarItems];

    for (final routine in routines.where((r) => r.firesOn(day))) {
      final hour = routine.scheduleHour ??
          switch (routine.anchor) {
            RoutineAnchor.morning => 8,
            RoutineAnchor.midday => 12,
            RoutineAnchor.evening => 18,
            RoutineAnchor.custom => 9,
          };
      final start = DateTime(
          day.year, day.month, day.day, hour, routine.scheduleMinute ?? 0);
      final minutes = routine.steps.fold<int>(
        0,
        (sum, step) => sum + (step.durationMinutes ?? 5),
      );
      items.add(TimelineItem(
        id: 'routine-${routine.id}',
        type: TimelineItemType.fixedAnchor,
        title: routine.name,
        subtitle: routine.isComplete
            ? 'Complete'
            : '${routine.steps.length} step${routine.steps.length == 1 ? '' : 's'}',
        start: start,
        end: start.add(Duration(minutes: minutes.clamp(15, 90))),
        isCompleted: routine.isComplete,
      ));
    }

    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      final start = task.dueDate ??
          DateTime(day.year, day.month, day.day, 9)
              .add(Duration(minutes: index * 45));
      items.add(TimelineItem(
        id: 'task-${task.id}',
        type: task.dueDate == null
            ? TimelineItemType.flexibleBlock
            : TimelineItemType.task,
        title: task.title,
        subtitle: task.notes,
        start: start,
        end: start.add(const Duration(minutes: 30)),
        task: task,
        isCompleted: task.isCompleted,
        isPaused: task.status == TaskStatus.paused,
      ));
    }

    items.sort(compareItems);
    return _withOpenSpace(items, day);
  }

  static int compareItems(TimelineItem a, TimelineItem b) {
    if (a.start == null && b.start == null) return a.id.compareTo(b.id);
    if (a.start == null) return 1;
    if (b.start == null) return -1;
    final time = a.start!.compareTo(b.start!);
    if (time != 0) return time;
    return a.type.index.compareTo(b.type.index);
  }

  List<TimelineItem> _withOpenSpace(List<TimelineItem> items, DateTime day) {
    if (items.isEmpty) return items;
    final result = <TimelineItem>[];
    for (final item in items) {
      if (result.isNotEmpty) {
        final previousEnd = result.last.end;
        if (previousEnd != null && item.start != null) {
          final gap = item.start!.difference(previousEnd);
          if (gap >= const Duration(minutes: 45)) {
            result.add(TimelineItem(
              id: 'space-${previousEnd.millisecondsSinceEpoch}',
              type: TimelineItemType.openSpace,
              title: 'Open space',
              subtitle: '${gap.inMinutes} minutes with no plan',
              start: previousEnd,
              end: item.start,
            ));
          }
        }
      }
      result.add(item);
    }
    return result;
  }
}

abstract class DaySummaryRefiner {
  const DaySummaryRefiner();
  Future<String?> refine(String deterministicSummary, TodayTimelineData data);
}

class DaySummary {
  const DaySummary();

  String build(TodayTimelineData data) {
    final remaining = data.items.where((item) => !item.isCompleted);
    final anchors = remaining
        .where((item) => item.type == TimelineItemType.fixedAnchor)
        .length;
    final flexible = remaining
        .where((item) => item.type == TimelineItemType.flexibleBlock)
        .length;
    if (anchors == 0 && flexible == 0) {
      return data.items.isEmpty
          ? 'Your day is open. Add one gentle next step when you are ready.'
          : 'Your planned anchors and flexible blocks are clear.';
    }
    if (anchors == 0) {
      return 'You have ${_count(flexible, 'flexible block')} left.';
    }
    if (flexible == 0) {
      return 'You have ${_count(anchors, 'anchor')} left.';
    }
    return 'You have ${_count(anchors, 'anchor')} and '
        '${_count(flexible, 'flexible block')} left.';
  }

  String _count(int count, String label) =>
      count == 1 ? 'one $label' : '$count ${label}s';
}
