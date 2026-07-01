// lib/data/habit_repository.dart
//
// Abstract repository for Habit CRUD and check-in recording.

import '../domain/habit.dart';

abstract class HabitRepository {
  /// All active habits with last-30-day check-ins attached.
  Stream<List<Habit>> watchActive();

  /// Record today's check-in for a habit. Upserts — safe to call twice.
  Future<void> checkIn(String habitId, {bool completed = true});

  /// Un-check today's check-in (user tapped by mistake).
  Future<void> uncheckToday(String habitId);

  Future<void> save(Habit habit);
  Future<void> archive(String habitId); // soft-delete: sets isActive = false
  Future<void> delete(String habitId);  // hard-delete with all check-ins
}
