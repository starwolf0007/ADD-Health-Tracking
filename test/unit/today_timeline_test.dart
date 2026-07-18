import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/executive/timeline_logic.dart';

void main() {
  final day = DateTime(2026, 7, 10);

  test('orders mixed items chronologically with stable overlap ordering', () {
    final task = Task(
      id: 'task',
      title: 'Write update',
      energy: EnergyLevel.medium,
      createdAt: day,
      dueDate: DateTime(2026, 7, 10, 10),
    );
    final routine = Routine(
      id: 'anchor',
      name: 'Morning anchor',
      anchor: RoutineAnchor.morning,
      scheduleHour: 8,
      createdAt: day,
    );
    final calendar = TimelineItem(
      id: 'calendar',
      type: TimelineItemType.calendarEvent,
      title: 'Stand-up',
      start: DateTime(2026, 7, 10, 9),
      end: DateTime(2026, 7, 10, 9, 30),
    );

    final items = const TodayTimelineBuilder().build(
      day: day,
      tasks: [task],
      routines: [routine],
      calendarItems: [calendar],
    );

    expect(
        items
            .where((item) => item.type != TimelineItemType.openSpace)
            .map((item) => item.id),
        ['routine-anchor', 'calendar', 'task-task']);
  });

  test('groups items into past, current, and upcoming at a fixed time', () {
    final now = DateTime(2026, 7, 10, 12);
    final items = [
      TimelineItem(
        id: 'past',
        type: TimelineItemType.task,
        title: 'Past',
        start: DateTime(2026, 7, 10, 9),
        end: DateTime(2026, 7, 10, 10),
      ),
      TimelineItem(
        id: 'current',
        type: TimelineItemType.calendarEvent,
        title: 'Current',
        start: DateTime(2026, 7, 10, 11, 30),
        end: DateTime(2026, 7, 10, 12, 30),
      ),
      TimelineItem(
        id: 'future',
        type: TimelineItemType.fixedAnchor,
        title: 'Future',
        start: DateTime(2026, 7, 10, 18),
      ),
    ];

    expect(items.map((item) => item.phaseAt(now)), [
      TimelinePhase.past,
      TimelinePhase.current,
      TimelinePhase.upcoming,
    ]);
  });

  test('deterministic summary does not require Lexi', () {
    final data = TodayTimelineData(
      items: [
        TimelineItem(
          id: 'anchor',
          type: TimelineItemType.fixedAnchor,
          title: 'Lunch',
          start: DateTime(2026, 7, 10, 12),
        ),
        TimelineItem(
          id: 'flex-1',
          type: TimelineItemType.flexibleBlock,
          title: 'Email',
          start: DateTime(2026, 7, 10, 13),
        ),
        TimelineItem(
          id: 'flex-2',
          type: TimelineItemType.flexibleBlock,
          title: 'Draft',
          start: DateTime(2026, 7, 10, 14),
        ),
      ],
      recommendedTask: null,
      hasCalendarPermission: false,
      lexiAvailable: false,
    );

    expect(const DaySummary().build(data),
        'You have one anchor and 2 flexible blocks left.');
  });

  test('summary omits item types with no remaining work', () {
    final data = TodayTimelineData(
      items: [
        TimelineItem(
          id: 'flex',
          type: TimelineItemType.flexibleBlock,
          title: 'Email',
          start: DateTime(2026, 7, 10, 13),
        ),
      ],
      recommendedTask: null,
      hasCalendarPermission: false,
      lexiAvailable: false,
    );

    expect(const DaySummary().build(data), 'You have one flexible block left.');
  });
}
