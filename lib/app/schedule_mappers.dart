import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/executive/day_resolver.dart';

extension ScheduleRuleRowMapping on ScheduleRuleRow {
  RuleSpec toRuleSpec() {
    final rawDays = byDay.split(',').map((value) => value.trim()).toList();
    final days = <int>{};
    for (final rawDay in rawDays) {
      final day = int.tryParse(rawDay);
      if (day == null) {
        throw InvalidScheduleRule(
          ruleId: id,
          field: 'byDay',
          value: byDay,
          reason: 'must contain only comma-separated ISO weekdays',
        );
      }
      days.add(day);
    }
    final rule = RuleSpec(
      id: id,
      name: name,
      byDay: days,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      commuteBeforeMin: commuteBeforeMin,
      commuteAfterMin: commuteAfterMin,
      exclusionCalendarId: exclusionCalendarId,
    );
    validateRule(rule);
    return rule;
  }
}

extension ScheduleExceptionRowMapping on ScheduleExceptionRow {
  ExceptionSpec toExceptionSpec() => ExceptionSpec(
        ruleId: ruleId,
        date: date,
        type: switch (type) {
          'skip' => ExceptionType.skip,
          'force' => ExceptionType.force,
          _ => throw InvalidScheduleRule(
              ruleId: ruleId,
              field: 'exception.type',
              value: type,
              reason: 'must be skip or force',
            ),
        },
      );
}

Future<Map<String, Set<String>>> loadHolidayCalendars(
  AppDatabase database,
  Iterable<RuleSpec> rules,
) async {
  final ids =
      rules.map((rule) => rule.exclusionCalendarId).whereType<String>().toSet();
  return {
    for (final id in ids) id: await database.fetchHolidayDates(id),
  };
}
