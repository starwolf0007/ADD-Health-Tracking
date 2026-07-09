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

  // ─── longestStreak ────────────────────────────────────────────────────────

  group('longestStreak', () {
    test('is 0 with no check-ins', () {
      expect(_habit([]).longestStreak, 0);
    });

    test('counts the best consecutive run, not just the current one', () {
      final habit = _habit([
        _checkIn(0, completed: true), // current run of 1
        _checkIn(1, completed: false), // breaks the run
        _checkIn(2, completed: true), // older run of 3
        _checkIn(3, completed: true),
        _checkIn(4, completed: true),
      ]);
      expect(habit.longestStreak, 3);
    });

    test('resets the run on an uncompleted check-in', () {
      final habit = _habit([
        _checkIn(0, completed: true),
        _checkIn(1, completed: false),
        _checkIn(2, completed: true),
      ]);
      expect(habit.longestStreak, 1);
    });
  });

  // ─── frequency applicability ───────────────────────────────────────────────

  group('frequency applicability (longestStreak)', () {
    // 2024-01-01 Mon, 02 Tue ... 06 Sat, 07 Sun.
    HabitCheckIn on(DateTime d, {bool completed = true}) => HabitCheckIn(
          id: 'ci-${d.day}',
          habitId: 'test-habit',
          date: d,
          completed: completed,
          createdAt: d,
        );

    test('weekdays habit ignores weekend completions', () {
      final habit = _habit(
        [
          on(DateTime(2024, 1, 6)), // Sat — not applicable
          on(DateTime(2024, 1, 7)), // Sun — not applicable
        ],
        frequency: HabitFrequency.weekdays,
      );
      expect(habit.longestStreak, 0);
    });

    test('weekends habit counts only weekend completions', () {
      final habit = _habit(
        [
          on(DateTime(2024, 1, 6)), // Sat
          on(DateTime(2024, 1, 7)), // Sun
          on(DateTime(2024, 1, 8)), // Mon — not applicable, breaks run
        ],
        frequency: HabitFrequency.weekends,
      );
      expect(habit.longestStreak, 2);
    });
  });

  // ─── HabitCheckIn.forToday ──────────────────────────────────────────────────

  group('HabitCheckIn.forToday', () {
    test('normalizes date to midnight and carries habitId/completed', () {
      final ci = HabitCheckIn.forToday(habitId: 'h1', completed: true);
      final now = DateTime.now();
      expect(ci.habitId, 'h1');
      expect(ci.completed, isTrue);
      expect(ci.date, DateTime(now.year, now.month, now.day));
      expect(ci.id, isNotEmpty);
    });
  });

  // ─── Habit.create / copyWith ────────────────────────────────────────────────

  group('Habit.create / copyWith', () {
    test('create sets defaults and generates an id', () {
      final habit = Habit.create(name: 'Water');
      expect(habit.name, 'Water');
      expect(habit.frequency, HabitFrequency.daily);
      expect(habit.isActive, isTrue);
      expect(habit.recentCheckIns, isEmpty);
      expect(habit.id, isNotEmpty);
    });

    test('copyWith preserves id/createdAt and overrides given fields', () {
      final habit = Habit.create(name: 'Water');
      final updated = habit.copyWith(name: 'Stretch', isActive: false);
      expect(updated.id, habit.id);
      expect(updated.createdAt, habit.createdAt);
      expect(updated.name, 'Stretch');
      expect(updated.isActive, isFalse);
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────

Habit _habit(
  List<HabitCheckIn> checkIns, {
  HabitFrequency frequency = HabitFrequency.daily,
}) {
  return Habit(
    id: 'test-habit',
    name: 'Test Habit',
    frequency: frequency,
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
