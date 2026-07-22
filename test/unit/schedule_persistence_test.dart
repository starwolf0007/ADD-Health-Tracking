import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/app/schedule_mappers.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/executive/day_resolver.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('new database seeds the PG&E rule and 2026 holiday calendar', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    final rules = (await database.fetchScheduleRules())
        .map((row) => row.toRuleSpec())
        .toList();
    final calendars = await loadHolidayCalendars(database, rules);

    expect(rules, hasLength(1));
    expect(rules.single.id, 'rule_work');
    expect(rules.single.byDay, {1, 2, 3, 4, 5});
    expect(rules.single.startMinutes, 360);
    expect(rules.single.endMinutes, 870);
    expect(rules.single.commuteBeforeMin, 20);
    expect(rules.single.commuteAfterMin, 20);
    expect(rules.single.exclusionCalendarId, 'pge_2026');
    expect(calendars['pge_2026'], hasLength(11));
    expect(calendars['pge_2026'], contains('2026-07-03'));

    expect(
      resolveDay(
        day: DateTime(2026, 7, 3),
        rules: rules,
        exceptions: const [],
        holidayCalendars: calendars,
      ),
      isEmpty,
    );
  });

  test('version 5 database migrates schedule tables and seed data', () async {
    final directory =
        await Directory.systemTemp.createTemp('neuroflow-schedule-v5');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/v5.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('PRAGMA user_version = 5');
    raw.close();

    final database = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(database.close);

    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = tables.map((row) => row.read<String>('name')).toSet();

    expect(
      names,
      containsAll({
        'holiday_calendar_entries',
        'schedule_rules',
        'schedule_exceptions',
      }),
    );
    expect(await database.fetchScheduleRules(), hasLength(1));
    expect(await database.fetchHolidayDates('pge_2026'), hasLength(11));
  });

  test('persisted exceptions map to typed resolver inputs', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.scheduleExceptions).insert(
          ScheduleExceptionsCompanion.insert(
            ruleId: 'rule_work',
            date: '2026-09-07',
            type: 'force',
          ),
        );

    final rows = await database.fetchScheduleExceptionsForDate('2026-09-07');
    final exception = rows.single.toExceptionSpec();

    expect(exception.ruleId, 'rule_work');
    expect(exception.date, '2026-09-07');
    expect(exception.type, ExceptionType.force);
  });

  test('malformed persisted weekday fails loudly with the rule id', () {
    const row = ScheduleRuleRow(
      id: 'bad_days',
      name: 'Bad',
      byDay: '1,x,5',
      startMinutes: 360,
      endMinutes: 870,
      commuteBeforeMin: 0,
      commuteAfterMin: 0,
      exclusionCalendarId: null,
    );

    expect(
      row.toRuleSpec,
      throwsA(isA<InvalidScheduleRule>()
          .having((error) => error.ruleId, 'ruleId', 'bad_days')
          .having((error) => error.field, 'field', 'byDay')),
    );
  });
}
