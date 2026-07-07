// lib/data/habit_repository_impl.dart
//
// Drift-backed HabitRepository.
// Assembles Habit domain objects with last-30-day check-ins.

import 'package:drift/drift.dart';

import '../domain/habit.dart';
import 'database.dart';
import 'habit_repository.dart';

class DriftHabitRepository implements HabitRepository {
  final AppDatabase _db;

  DriftHabitRepository(this._db);

  // ------------------------------------------------------------------
  // Mappers
  // ------------------------------------------------------------------

  Habit _rowsToHabit(HabitRow row, List<HabitCheckInRow> checkInRows) {
    return Habit(
      id: row.id,
      name: row.name,
      notes: row.notes,
      frequency: _freqFromString(row.frequency),
      isActive: row.isActive,
      createdAt: row.createdAt,
      recentCheckIns: checkInRows.map(_checkInRowToDomain).toList(),
    );
  }

  HabitCheckIn _checkInRowToDomain(HabitCheckInRow row) {
    return HabitCheckIn(
      id: row.id,
      habitId: row.habitId,
      date: row.date,
      completed: row.completed,
      createdAt: row.createdAt,
    );
  }

  HabitsCompanion _habitToCompanion(Habit h) {
    return HabitsCompanion(
      id: Value(h.id),
      name: Value(h.name),
      notes: Value(h.notes),
      frequency: Value(_freqToString(h.frequency)),
      isActive: Value(h.isActive),
      createdAt: Value(h.createdAt),
    );
  }

  // ------------------------------------------------------------------
  // Interface
  // ------------------------------------------------------------------

  @override
  Stream<List<Habit>> watchActive() {
    // Use a manual deduplication mechanism to prevent duplicate emissions.
    // The asyncMap can re-emit the same data multiple times, causing infinite
    // duplication in the UI. Track the last emission and only emit if changed.
    List<Habit>? lastEmission;

    return _db.watchActiveHabits().asyncMap((rows) async {
      final result = <Habit>[];
      for (final row in rows) {
        final checkIns = await _db.fetchRecentCheckIns(row.id);
        result.add(_rowsToHabit(row, checkIns));
      }
      return result;
    }).where((nextEmission) {
      // Deduplicate: only emit if the list of habit IDs changed.
      // Compares habit IDs (not the full objects) to detect meaningful changes.
      if (lastEmission == null) {
        lastEmission = nextEmission;
        return true;
      }

      if (lastEmission!.length != nextEmission.length) {
        lastEmission = nextEmission;
        return true;
      }

      // Check if any habit ID is different
      for (int i = 0; i < lastEmission!.length; i++) {
        if (lastEmission![i].id != nextEmission[i].id) {
          lastEmission = nextEmission;
          return true;
        }
      }

      // No change detected; suppress duplicate emission
      return false;
    });
  }

  @override
  Future<void> checkIn(String habitId, {bool completed = true}) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await _db.upsertCheckIn(HabitCheckInsCompanion(
      id: Value('${habitId}_${today.toIso8601String()}'),
      habitId: Value(habitId),
      date: Value(today),
      completed: Value(completed),
      createdAt: Value(now),
    ));
  }

  @override
  Future<void> uncheckToday(String habitId) async {
    await _db.deleteCheckInForToday(habitId);
  }

  @override
  Future<void> save(Habit habit) async {
    await _db.upsertHabit(_habitToCompanion(habit));
  }

  @override
  Future<void> archive(String habitId) async {
    await _db.archiveHabit(habitId);
  }

  @override
  Future<void> delete(String habitId) async {
    await _db.deleteHabit(habitId);
  }

  // ------------------------------------------------------------------
  // String converters
  // ------------------------------------------------------------------

  HabitFrequency _freqFromString(String s) {
    switch (s) {
      case 'weekdays':
        return HabitFrequency.weekdays;
      case 'weekends':
        return HabitFrequency.weekends;
      default:
        return HabitFrequency.daily;
    }
  }

  String _freqToString(HabitFrequency f) {
    switch (f) {
      case HabitFrequency.weekdays:
        return 'weekdays';
      case HabitFrequency.weekends:
        return 'weekends';
      case HabitFrequency.daily:
        return 'daily';
    }
  }
}
