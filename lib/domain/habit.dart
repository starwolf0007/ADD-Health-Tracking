// lib/domain/habit.dart
//
// Habit domain models — pure, no Flutter/Drift.
//
// ADHD UX intent:
//   • A habit is a single daily intention, not a complex tracker.
//   • Completion uses a rolling 30-day rate + monthly skip budget
//     (forgiveness), never a consecutive-day counter that zeros on a miss.
//   • Check-ins are binary: done or not. No "partial" states that invite
//     over-analysis.
//   • Habits are meant to be few (3 max surfaced per day) to avoid overwhelm.

import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Frequency
// ---------------------------------------------------------------------------

enum HabitFrequency {
  daily, // every day
  weekdays, // Mon–Fri only
  weekends, // Sat–Sun only
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
    final today = DateTime(now.year, now.month, now.day);
    return HabitCheckIn(
      id: const Uuid().v4(),
      habitId: habitId,
      date: today,
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

  /// Applicable misses allowed in the current calendar month before the
  /// forgiveness budget is exhausted. Internal metric only — never shown
  /// as a raw count in the UI (§13).
  static const int monthlySkipBudget = 5;

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
    final today = _today();
    return recentCheckIns.any((c) => _sameDay(c.date, today) && c.completed);
  }

  /// Rolling completion rate over the last 30 calendar days, counting only
  /// days that apply for this habit's frequency. Returns 0.0 when there are
  /// no applicable days yet.
  double get completionRate30d {
    final today = _today();
    var applicable = 0;
    var completed = 0;

    for (var i = 0; i < 30; i++) {
      final day = today.subtract(Duration(days: i));
      if (!_isApplicable(day)) continue;
      applicable++;
      final hit = recentCheckIns.any(
        (c) => _sameDay(c.date, day) && c.completed,
      );
      if (hit) completed++;
    }

    if (applicable == 0) return 0.0;
    return completed / applicable;
  }

  /// Remaining skips in the current calendar month (budget minus applicable
  /// days that were not completed). Clamped at 0. Internal only.
  int get skipsRemainingThisMonth {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final today = _today();

    var misses = 0;
    for (var day = monthStart;
        !day.isAfter(today);
        day = day.add(const Duration(days: 1))) {
      if (!_isApplicable(day)) continue;
      final hit = recentCheckIns.any(
        (c) => _sameDay(c.date, day) && c.completed,
      );
      if (!hit) misses++;
    }

    final remaining = monthlySkipBudget - misses;
    return remaining < 0 ? 0 : remaining;
  }

  bool _isApplicable(DateTime date) {
    switch (frequency) {
      case HabitFrequency.daily:
        return true;
      case HabitFrequency.weekdays:
        return date.weekday >= DateTime.monday &&
            date.weekday <= DateTime.friday;
      case HabitFrequency.weekends:
        return date.weekday == DateTime.saturday ||
            date.weekday == DateTime.sunday;
    }
  }

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
