import 'package:flutter_test/flutter_test.dart';

import 'package:neuroflow/executive/day_resolver.dart';

const pge2026 = 'pge_2026';

const workRule = RuleSpec(
  id: 'rule_work',
  name: 'PG&E Work Schedule',
  byDay: {1, 2, 3, 4, 5},
  startMinutes: 360,
  endMinutes: 870,
  commuteBeforeMin: 20,
  commuteAfterMin: 20,
  exclusionCalendarId: pge2026,
);

final holidays = <String, Set<String>>{
  pge2026: {
    '2026-01-01',
    '2026-01-19',
    '2026-02-16',
    '2026-05-25',
    '2026-06-19',
    '2026-07-03',
    '2026-09-07',
    '2026-11-11',
    '2026-11-26',
    '2026-11-27',
    '2026-12-25',
  },
};

List<ResolvedBlock> resolve(DateTime day,
        {List<ExceptionSpec> exceptions = const []}) =>
    resolveDay(
      day: day,
      rules: const [workRule],
      exceptions: exceptions,
      holidayCalendars: holidays,
    );

void main() {
  group('recurrence baseline', () {
    test('normal weekday emits commute + work + commute, sorted', () {
      final blocks = resolve(DateTime(2026, 7, 21));
      expect(blocks.length, 3);
      expect(blocks[0].kind, BlockKind.commute);
      expect(blocks[0].startMinutes, 340);
      expect(blocks[1].label, 'PG&E Work Schedule');
      expect(blocks[1].startMinutes, 360);
      expect(blocks[1].endMinutes, 870);
      expect(blocks[2].kind, BlockKind.commute);
      expect(blocks[2].endMinutes, 890);
    });

    test('ordinary Saturday emits nothing', () {
      expect(resolve(DateTime(2026, 7, 25)), isEmpty);
    });
  });

  group('priority: exception > holiday > recurrence', () {
    test('holiday suppresses work block', () {
      expect(resolve(DateTime(2026, 9, 7)), isEmpty);
    });

    test('force exception beats holiday', () {
      final blocks = resolve(
        DateTime(2026, 9, 7),
        exceptions: const [
          ExceptionSpec(
            ruleId: 'rule_work',
            date: '2026-09-07',
            type: ExceptionType.force,
          ),
        ],
      );
      expect(blocks.length, 3);
    });

    test('skip exception suppresses a normal weekday', () {
      final blocks = resolve(
        DateTime(2026, 7, 21),
        exceptions: const [
          ExceptionSpec(
            ruleId: 'rule_work',
            date: '2026-07-21',
            type: ExceptionType.skip,
          ),
        ],
      );
      expect(blocks, isEmpty);
    });

    test('force exception creates Saturday overtime blocks', () {
      final blocks = resolve(
        DateTime(2026, 7, 25),
        exceptions: const [
          ExceptionSpec(
            ruleId: 'rule_work',
            date: '2026-07-25',
            type: ExceptionType.force,
          ),
        ],
      );
      expect(blocks.length, 3);
    });
  });

  group('validation and known edges', () {
    test('Jan 1 2027 incorrectly renders as work until 2027 import', () {
      expect(resolve(DateTime(2026, 12, 31)).length, 3);
      expect(resolve(DateTime(2027, 1, 1)).length, 3);
    });

    test('start at or after end throws typed failure with rule id', () {
      const bad = RuleSpec(
        id: 'bad_range',
        name: 'Bad',
        byDay: {1},
        startMinutes: 870,
        endMinutes: 360,
      );
      expect(
        () => resolveDay(
          day: DateTime(2026, 7, 20),
          rules: const [bad],
          exceptions: const [],
          holidayCalendars: const {},
        ),
        throwsA(isA<InvalidScheduleRule>()
            .having((error) => error.ruleId, 'ruleId', 'bad_range')),
      );
    });

    test('invalid recurrence weekday throws typed failure with rule id', () {
      const bad = RuleSpec(
        id: 'bad_weekday',
        name: 'Bad',
        byDay: {0, 8},
        startMinutes: 360,
        endMinutes: 870,
      );
      expect(
        () => resolveDay(
          day: DateTime(2026, 7, 20),
          rules: const [bad],
          exceptions: const [],
          holidayCalendars: const {},
        ),
        throwsA(isA<InvalidScheduleRule>()
            .having((error) => error.ruleId, 'ruleId', 'bad_weekday')
            .having((error) => error.field, 'field', 'byDay')),
      );
    });

    test('commute spilling past midnight throws with rule id', () {
      const bad = RuleSpec(
        id: 'bad_commute',
        name: 'Bad',
        byDay: {1},
        startMinutes: 10,
        endMinutes: 1435,
        commuteBeforeMin: 20,
        commuteAfterMin: 20,
      );
      expect(
        () => resolveDay(
          day: DateTime(2026, 7, 20),
          rules: const [bad],
          exceptions: const [],
          holidayCalendars: const {},
        ),
        throwsA(isA<InvalidScheduleRule>()
            .having((error) => error.ruleId, 'ruleId', 'bad_commute')),
      );
    });
  });
}
