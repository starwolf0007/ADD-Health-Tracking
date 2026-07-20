import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/executive/work_schedule.dart';

void main() {
  group('PermanentWorkSchedule', () {
    test('resolves commute and work blocks on a normal weekday', () {
      final blocks = defaultPgeWorkSchedule.resolve(DateTime(2026, 7, 2));

      expect(blocks, hasLength(3));
      expect(blocks[0].kind, ResolvedWorkBlockKind.commuteToWork);
      expect(blocks[0].start, DateTime(2026, 7, 2, 5, 40));
      expect(blocks[0].end, DateTime(2026, 7, 2, 6));
      expect(blocks[1].kind, ResolvedWorkBlockKind.work);
      expect(blocks[1].start, DateTime(2026, 7, 2, 6));
      expect(blocks[1].end, DateTime(2026, 7, 2, 14, 30));
      expect(blocks[2].kind, ResolvedWorkBlockKind.commuteHome);
      expect(blocks[2].end, DateTime(2026, 7, 2, 14, 50));
    });

    test('suppresses work on the observed Independence Day holiday', () {
      final blocks = defaultPgeWorkSchedule.resolve(DateTime(2026, 7, 3));

      expect(blocks, isEmpty);
    });

    test('does not fire on weekends', () {
      final blocks = defaultPgeWorkSchedule.resolve(DateTime(2026, 7, 4));

      expect(blocks, isEmpty);
    });

    test('manual work override wins over holiday suppression', () {
      final schedule = PermanentWorkSchedule(
        id: 'test-work',
        title: 'Work',
        startHour: 6,
        startMinute: 0,
        endHour: 14,
        endMinute: 30,
        holidays: pgeWorkHolidays2026,
        overrides: {
          DateTime(2026, 7, 3): WorkdayOverride.work,
        },
      );

      expect(schedule.resolve(DateTime(2026, 7, 3)), hasLength(1));
    });

    test('manual skip override wins over weekday recurrence', () {
      final schedule = PermanentWorkSchedule(
        id: 'test-work',
        title: 'Work',
        startHour: 6,
        startMinute: 0,
        endHour: 14,
        endMinute: 30,
        overrides: {
          DateTime(2026, 7, 2): WorkdayOverride.skip,
        },
      );

      expect(schedule.resolve(DateTime(2026, 7, 2)), isEmpty);
    });
  });
}
