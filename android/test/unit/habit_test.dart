// test/unit/habit_test.dart
//
// Unit tests for Habit domain model — streak computation and today-check logic.
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

  // ─── currentStreak ────────────────────────────────────────────────────────

  group('currentStreak', () {
    test('is 0 with no check-ins', () {
      expect(_habit([]).currentStreak, 0);
    });

    test('is 1 when only today is checked', () {
      final habit = _habit([_checkIn(0, completed: true)]);
      expect(habit.currentStreak, 1);
    });

    test('counts consecutive days ending today', () {
      final habit = _habit([
        _checkIn(0, completed: true),
        _checkIn(1, completed: true),
        _checkIn(2, completed: true),
      ]);
      expect(habit.currentStreak, 3);
    });

    test('breaks at a missed day', () {
      final habit = _habit([
        _checkIn(0, completed: true),
        // day 1 missed
        _checkIn(2, completed: true),
        _checkIn(3, completed: true),
      ]);
      expect(habit.currentStreak, 1); // only today counts
    });

    test('is 0 when today is not checked even if yesterday was', () {
      final habit = _habit([_checkIn(1, completed: true)]);
      expect(habit.currentStreak, 0);
    });

    test('does not count uncompleted check-ins in streak', () {
      final habit = _habit([
        _checkIn(0, completed: false),
        _checkIn(1, completed: true),
      ]);
      expect(habit.currentStreak, 0);
    });
  });

  // ─── Routine domain helpers ───────────────────────────────────────────────
  // (Basic sanity — full routine tests live in routine_test.dart)
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
  final date = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: daysAgo));
  return HabitCheckIn(
    id: 'ci-$daysAgo',
    habitId: 'test-habit',
    date: date,
    completed: completed,
    createdAt: date,
  );
}
