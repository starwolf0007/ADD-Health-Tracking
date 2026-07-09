// lib/domain/habit.dart
//
// Habit domain models — pure, no Flutter/Drift.
//
// ADHD UX intent:
//   • A habit is a single daily intention, not a complex tracker.
//   • Streaks are shown but breaking one resets to 0 — no shame messaging in code.
//   • Check-ins are binary: done or not. No "partial" states that invite over-analysis.
//   • Habits are meant to be few (3 max surfaced per day) to avoid overwhelm.

import 'package:uuid/uuid.dart';

import 'package:neuroflow/domain/date_utils.dart';

// ---------------------------------------------------------------------------
// Frequency
// ---------------------------------------------------------------------------

enum HabitFrequency {
  daily,      // every day
  weekdays,   // Mon–Fri only
  weekends,   // Sat–Sun only
}

// ---------------------------------------------------------------------------
// HabitCheckIn — a single day's completion record
// ---------------------------------------------------------------------------

class HabitCheckIn {
  final String id;
  final String habitId;
  final DateTime date; // normalized to midnight local time
  final bool completed;
  final DateTime createdAt;

  const HabitCheckIn({
    required this.id,
    required this.habitId,
    required this.date,
    required this.completed,
    required this.createdAt,
  });

  factory HabitCheckIn.forToday({
    required String habitId,
    required bool completed,
  }) {
    final now = DateTime.now();
    return HabitCheckIn(
      id: const Uuid().v4(),
      habitId: habitId,
      date: dateOnly(now),
      completed: completed,
      createdAt: now,
    );
  }
}

// ---------------------------------------------------------------------------
// Habit
// ---------------------------------------------------------------------------

class Habit {
  final String id;
  final String name;
  final String? notes;
  final HabitFrequency frequency;
  final bool isActive;
  final DateTime createdAt;

  // Computed at query time — not stored
  final List<HabitCheckIn> recentCheckIns; // last 30 days, descending

  const Habit({
    required this.id,
    required this.name,
    this.notes,
    required this.frequency,
    this.isActive = true,
    required this.createdAt,
    this.recentCheckIns = const [],
  });

  factory Habit.create({
    required String name,
    String? notes,
    HabitFrequency frequency = HabitFrequency.daily,
  }) {
    return Habit(
      id: const Uuid().v4(),
      name: name,
      notes: notes,
      frequency: frequency,
      createdAt: DateTime.now(),
    );
  }

  Habit copyWith({
    String? name,
    String? notes,
    HabitFrequency? frequency,
    bool? isActive,
    List<HabitCheckIn>? recentCheckIns,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      frequency: frequency ?? this.frequency,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      recentCheckIns: recentCheckIns ?? this.recentCheckIns,
    );
  }

  // ------------------------------------------------------------------
  // Computed helpers
  // ------------------------------------------------------------------

  /// Whether today's check-in is already marked.
  bool get isCheckedToday {
    final currentDay = today();
    return recentCheckIns
        .any((c) => isSameDay(c.date, currentDay) && c.completed);
  }

  /// Current streak — consecutive applicable days completed, counting back from today.
  int get currentStreak {
    if (recentCheckIns.isEmpty) return 0;

    final sorted = List<HabitCheckIn>.from(recentCheckIns)
      ..sort((a, b) => b.date.compareTo(a.date));

    int streak = 0;
    DateTime cursor = today();

    for (final checkIn in sorted) {
      if (!isSameDay(checkIn.date, cursor)) break;
      if (!checkIn.completed) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
      // Skip non-applicable days (weekday/weekend filtering)
      while (!_isApplicable(cursor)) {
        cursor = cursor.subtract(const Duration(days: 1));
      }
    }
    return streak;
  }

  /// Longest streak ever (from recentCheckIns — capped at 30 days).
  int get longestStreak {
    if (recentCheckIns.isEmpty) return 0;
    final sorted = List<HabitCheckIn>.from(recentCheckIns)
      ..sort((a, b) => a.date.compareTo(b.date));

    int best = 0;
    int current = 0;
    for (final c in sorted) {
      if (c.completed && _isApplicable(c.date)) {
        current++;
        if (current > best) best = current;
      } else {
        current = 0;
      }
    }
    return best;
  }

  bool _isApplicable(DateTime date) {
    switch (frequency) {
      case HabitFrequency.daily:
        return true;
      case HabitFrequency.weekdays:
        return date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;
      case HabitFrequency.weekends:
        return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    }
  }
}
