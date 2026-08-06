// test/unit/habit_test.dart
//
// Unit tests for Habit domain model — check-in, rolling rate, skip budget.
// Run with: dart test test/unit/habit_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/habit.dart';

void main() {
  // ─── isCheckedToday ───────────────────────────────────────────────────────

  group('isCheckedToday', () {
    test('returns false when no check-ins', () {
      final habit = _habit([]);
      expect(habit.isCheckedToday, isFalse);
    });

    test('returns true when completed today', () {
      final habit = _habit([_checkIn(0, completed: true)]);
      expect(habit.isCheckedToday, isTrue);
    });

    test('returns false when check-in exists but not completed', () {
      final habit = _habit([_checkIn(0, completed: false)]);
      expect(habit.isCheckedToday, isFalse);
    });

    test('returns false when only yesterday was checked', () {
      final habit = _habit([_checkIn(1, completed: true)]);
      expect(habit.isCheckedToday, isFalse);
    });
  });

  // ─── completionRate30d ────────────────────────────────────────────────────

  group('completionRate30d', () {
    test('is 0 with no check-ins', () {
      expect(_habit([]).completionRate30d, 0.0);
    });

    test('is 1.0 when every applicable day in window is complete', () {
      final checkIns = [
        for (var i = 0; i < 30; i++) _checkIn(i, completed: true),
      ];
      expect(_habit(checkIns).completionRate30d, 1.0);
    });

    test('reflects partial completion without zeroing on a miss', () {
      // Today + yesterday complete; day-before missed — rate stays > 0.
      final habit = _habit([
        _checkIn(0, completed: true),
        _checkIn(1, completed: true),
        // day 2 absent = miss
      ]);
      final rate = habit.completionRate30d;
      expect(rate, greaterThan(0.0));
      expect(rate, lessThan(1.0));
    });

    test('a single miss does not collapse the whole history', () {
      final checkIns = [
        for (var i = 0; i < 10; i++)
          if (i != 3) _checkIn(i, completed: true),
      ];
      final rate = _habit(checkIns).completionRate30d;
      // 9 of 30 applicable days if daily → 0.3; importantly not 0.
      expect(rate, greaterThan(0.2));
      expect(rate, lessThan(0.5));
    });
  });

  // ─── skipsRemainingThisMonth ──────────────────────────────────────────────

  group('skipsRemainingThisMonth', () {
    test('starts at full budget with no misses recorded this month', () {
      // Completing every day so far this month leaves full budget.
      final now = DateTime.now();
      final dayOfMonth = now.day;
      final checkIns = [
        for (var i = 0; i < dayOfMonth; i++) _checkIn(i, completed: true),
      ];
      expect(
        _habit(checkIns).skipsRemainingThisMonth,
        Habit.monthlySkipBudget,
      );
    });

    test('decrements for each applicable miss this month', () {
      final now = DateTime.now();
      // Leave today and yesterday incomplete; complete the rest of the month.
      final checkIns = <HabitCheckIn>[
        for (var i = 2; i < now.day; i++) _checkIn(i, completed: true),
      ];
      final remaining = _habit(checkIns).skipsRemainingThisMonth;
      expect(remaining, lessThan(Habit.monthlySkipBudget));
      expect(remaining, greaterThanOrEqualTo(0));
    });

    test('never goes below zero', () {
      // Far more misses than the budget.
      final habit = _habit([]);
      expect(habit.skipsRemainingThisMonth, greaterThanOrEqualTo(0));
    });

    test('brand new habit does not charge skips for days before it was created',
        () {
      final habit = Habit(
        id: 'new-habit',
        name: 'New Habit',
        frequency: HabitFrequency.daily,
        createdAt: DateTime(2026, 8, 15), // fixed — guarantees a real gap
        // from month start regardless
        // of when this test runs
        recentCheckIns: [],
      );
      // Only Aug 15 is applicable under the fix; Aug 1–14 must not count
      // as misses even though they're within the month.
      expect(habit.getSkipsRemainingAt(DateTime(2026, 8, 15)),
          Habit.monthlySkipBudget - 1);
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────

Habit _habit(List<HabitCheckIn> checkIns) {
  return Habit(
    id: 'test-habit',
    name: 'Test Habit',
    frequency: HabitFrequency.daily,
    createdAt: DateTime.now().subtract(const Duration(days: 30)),
    recentCheckIns: checkIns,
  );
}

/// daysAgo = 0 means today, 1 = yesterday, etc.
HabitCheckIn _checkIn(int daysAgo, {required bool completed}) {
  final now = DateTime.now();
  final date =
      DateTime(now.year, now.month, now.day).subtract(Duration(days: daysAgo));
  return HabitCheckIn(
    id: 'ci-$daysAgo',
    habitId: 'test-habit',
    date: date,
    completed: completed,
    createdAt: date,
  );
}
