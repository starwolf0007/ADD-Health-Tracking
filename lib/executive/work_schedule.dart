// lib/executive/work_schedule.dart
//
// Deterministic permanent-work schedule resolution. Pure Dart: no Flutter,
// Drift, Google, or intelligence dependency.

import 'package:neuroflow/executive/timeline_logic.dart';

enum WorkdayOverride { work, skip }

class WorkHoliday {
  final DateTime date;
  final String name;

  const WorkHoliday(this.date, this.name);
}

class PermanentWorkSchedule {
  final String id;
  final String title;
  final int startHour;
  final int startMinute;
  final int endHour;
  final int endMinute;
  final int commuteBeforeMinutes;
  final int commuteAfterMinutes;
  final Set<int> weekdays;
  final List<WorkHoliday> holidays;
  final Map<DateTime, WorkdayOverride> overrides;

  const PermanentWorkSchedule({
    required this.id,
    required this.title,
    required this.startHour,
    required this.startMinute,
    required this.endHour,
    required this.endMinute,
    this.commuteBeforeMinutes = 0,
    this.commuteAfterMinutes = 0,
    this.weekdays = const {
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    },
    this.holidays = const [],
    this.overrides = const {},
  });

  List<TimelineItem> resolve(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final override = overrides[_dateOnly(date)];

    if (override == WorkdayOverride.skip) return const [];
    if (override != WorkdayOverride.work) {
      if (!weekdays.contains(date.weekday)) return const [];
      if (_holidayFor(date) != null) return const [];
    }

    final workStart = DateTime(
      date.year,
      date.month,
      date.day,
      startHour,
      startMinute,
    );
    final workEnd = DateTime(
      date.year,
      date.month,
      date.day,
      endHour,
      endMinute,
    );

    final items = <TimelineItem>[];
    if (commuteBeforeMinutes > 0) {
      items.add(TimelineItem(
        id: '$id-commute-in-${_key(date)}',
        type: TimelineItemType.calendarEvent,
        title: 'Commute to work',
        subtitle: 'Fixed block',
        start: workStart.subtract(Duration(minutes: commuteBeforeMinutes)),
        end: workStart,
      ));
    }

    items.add(TimelineItem(
      id: '$id-work-${_key(date)}',
      type: TimelineItemType.calendarEvent,
      title: title,
      subtitle: 'Fixed block · permanent schedule',
      start: workStart,
      end: workEnd,
    ));

    if (commuteAfterMinutes > 0) {
      items.add(TimelineItem(
        id: '$id-commute-home-${_key(date)}',
        type: TimelineItemType.calendarEvent,
        title: 'Commute home',
        subtitle: 'Fixed block',
        start: workEnd,
        end: workEnd.add(Duration(minutes: commuteAfterMinutes)),
      ));
    }

    return items;
  }

  WorkHoliday? _holidayFor(DateTime date) {
    for (final holiday in holidays) {
      if (_sameDate(holiday.date, date)) return holiday;
    }
    return null;
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _key(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

const pgeWorkHolidays2026 = <WorkHoliday>[
  WorkHoliday(DateTime(2026, 1, 1), "New Year's Day"),
  WorkHoliday(DateTime(2026, 1, 19), 'Martin Luther King Jr. Day'),
  WorkHoliday(DateTime(2026, 2, 16), "Presidents' Day"),
  WorkHoliday(DateTime(2026, 5, 25), 'Memorial Day'),
  WorkHoliday(DateTime(2026, 6, 19), 'Juneteenth'),
  WorkHoliday(DateTime(2026, 7, 3), 'Independence Day (Observed)'),
  WorkHoliday(DateTime(2026, 9, 7), 'Labor Day'),
  WorkHoliday(DateTime(2026, 11, 11), 'Veterans Day'),
  WorkHoliday(DateTime(2026, 11, 26), 'Thanksgiving Holiday'),
  WorkHoliday(DateTime(2026, 11, 27), 'Thanksgiving Holiday (Day 2)'),
  WorkHoliday(DateTime(2026, 12, 25), 'Christmas Day'),
];

const defaultPgeWorkSchedule = PermanentWorkSchedule(
  id: 'pge-work',
  title: 'Work',
  startHour: 6,
  startMinute: 0,
  endHour: 14,
  endMinute: 30,
  commuteBeforeMinutes: 20,
  commuteAfterMinutes: 20,
  holidays: pgeWorkHolidays2026,
);
