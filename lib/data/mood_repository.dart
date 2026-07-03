// lib/data/mood_repository.dart
//
// Interface + Drift implementation for MoodLogs (v2, spec §6 trigger).
//
// §2.8 HARD RULE: this repository has no sync hooks, enqueues nothing,
// and must never gain a mirror path. Mood data lives and dies on-device.

import 'package:drift/drift.dart';

import '../domain/mood.dart';
import 'database.dart';

abstract class MoodRepository {
  /// Latest check-in from today, or null if none yet.
  Stream<MoodLog?> watchToday();

  /// All check-ins in the trailing [days] window, oldest first.
  Stream<List<MoodLog>> watchRecent({int days = 7});

  Future<void> log(MoodLog entry);
}

class DriftMoodRepository implements MoodRepository {
  final AppDatabase _db;

  DriftMoodRepository(this._db);

  MoodLog _rowToLog(MoodLogRow row) => MoodLog(
        id: row.id,
        level: MoodLevelX.fromScore(row.level),
        note: row.note,
        loggedAt: row.loggedAt,
      );

  @override
  Stream<MoodLog?> watchToday() => _db
      .watchTodayLatestMood()
      .map((row) => row == null ? null : _rowToLog(row));

  @override
  Stream<List<MoodLog>> watchRecent({int days = 7}) =>
      _db.watchRecentMoods(days).map((rows) => rows.map(_rowToLog).toList());

  @override
  Future<void> log(MoodLog entry) => _db.insertMoodLog(MoodLogsCompanion(
        id: Value(entry.id),
        level: Value(entry.level.score),
        note: Value(entry.note),
        loggedAt: Value(entry.loggedAt),
      ));
}
