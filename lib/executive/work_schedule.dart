// lib/executive/work_schedule.dart
//
// Deterministic permanent-work schedule resolution. Pure Dart: no Flutter,
// Drift, Google, or intelligence dependency.

enum WorkdayOverride { work, skip }

enum ResolvedWorkBlockKind { commuteToWork, work, commuteHome }

class WorkHoliday {
  final int year;
  final int month;
  final int day;
  final String name;

  const WorkHoliday(this.year, this.month, this.day, this.name);

  bool matches(DateTime value) =>
      value.year == year && value.month == month && value.day == day;
}

class ResolvedWorkBlock {
  final String id;
  final ResolvedWorkBlockKind kind;
  final String title;
  final DateTime start;
  final DateTime end;

  const ResolvedWorkBlock({
    required this.id,
    required this.kind,
    required this.title,
    required this.start,
    required this.end,
  });
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

  List<ResolvedWorkBlock> resolve(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final override = _overrideFor(date);

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

    final blocks = <ResolvedWorkBlock>[];
    if (commuteBeforeMinutes > 0) {
      blocks.add(ResolvedWorkBlock(
        id: '$id-commute-in-${_key(date)}',
        kind: ResolvedWorkBlockKind.commuteToWork,
        title: 'Commute to work',
        start: workStart.subtract(Duration(minutes: commuteBeforeMinutes)),
        end: workStart,
      ));
    }

    blocks.add(ResolvedWorkBlock(
      id: '$id-work-${_key(date)}',
      kind: ResolvedWorkBlockKind.work,
      title: title,
      start: workStart,
      end: workEnd,
    ));

    if (commuteAfterMinutes > 0) {
      blocks.add(ResolvedWorkBlock(
        id: '$id-commute-home-${_key(date)}',
        kind: ResolvedWorkBlockKind.commuteHome,
        title: 'Commute home',
        start: workEnd,
        end: workEnd.add(Duration(minutes: commuteAfterMinutes)),
      ));
    }

    return blocks;
  }

  WorkdayOverride? _overrideFor(DateTime date) {
    for (final entry in overrides.entries) {
      if (_sameDate(entry.key, date)) return entry.value;
    }
    return null;
  }

  WorkHoliday? _holidayFor(DateTime date) {
    for (final holiday in holidays) {
      if (holiday.matches(date)) return holiday;
    }
    return null;
  }
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _key(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

const pgeWorkHolidays2026 = <WorkHoliday>[
  WorkHoliday(2026, 1, 1, "New Year's Day"),
  WorkHoliday(2026, 1, 19, 'Martin Luther King Jr. Day'),
  WorkHoliday(2026, 2, 16, "Presidents' Day"),
  WorkHoliday(2026, 5, 25, 'Memorial Day'),
  WorkHoliday(2026, 6, 19, 'Juneteenth'),
  WorkHoliday(2026, 7, 3, 'Independence Day (Observed)'),
  WorkHoliday(2026, 9, 7, 'Labor Day'),
  WorkHoliday(2026, 11, 11, 'Veterans Day'),
  WorkHoliday(2026, 11, 26, 'Thanksgiving Holiday'),
  WorkHoliday(2026, 11, 27, 'Thanksgiving Holiday (Day 2)'),
  WorkHoliday(2026, 12, 25, 'Christmas Day'),
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
