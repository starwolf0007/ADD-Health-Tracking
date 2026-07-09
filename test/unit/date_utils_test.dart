// test/unit/date_utils_test.dart
//
// Unit tests for the shared calendar-day helpers.
// Run with: dart test test/unit/date_utils_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/date_utils.dart';

void main() {
  group('dateOnly', () {
    test('strips the time-of-day component', () {
      final result = dateOnly(DateTime(2026, 7, 9, 21, 36, 42, 500));
      expect(result, DateTime(2026, 7, 9));
    });

    test('is idempotent on a midnight value', () {
      final midnight = DateTime(2026, 1, 1);
      expect(dateOnly(midnight), midnight);
    });
  });

  group('today', () {
    test('has no time-of-day component', () {
      final t = today();
      expect(t.hour, 0);
      expect(t.minute, 0);
      expect(t.second, 0);
      expect(t.millisecond, 0);
    });
  });

  group('isSameDay', () {
    test('true for two instants on the same day', () {
      expect(
        isSameDay(DateTime(2026, 7, 9, 1), DateTime(2026, 7, 9, 23, 59)),
        isTrue,
      );
    });

    test('false across a day boundary', () {
      expect(
        isSameDay(DateTime(2026, 7, 9, 23, 59), DateTime(2026, 7, 10, 0, 1)),
        isFalse,
      );
    });

    test('false for the same day-of-month in different months', () {
      expect(isSameDay(DateTime(2026, 6, 9), DateTime(2026, 7, 9)), isFalse);
    });
  });
}
