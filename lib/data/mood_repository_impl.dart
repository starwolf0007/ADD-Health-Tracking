// lib/data/mood_repository_impl.dart
//
// Drift-backed MoodRepository. Local-only by design — mood never enters the
// sync queue (§2.8), which is why this implementation takes no SyncQueue.

import 'package:drift/drift.dart';

import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/domain/mood_repository.dart';
import 'package:neuroflow/data/database.dart';

class DriftMoodRepository implements MoodRepository {
  final AppDatabase _db;

  DriftMoodRepository(this._db);

  @override
  Stream<MoodLog?> watchTodayLatest() =>
      _db.watchTodayLatestMood().map(_toDomainNullable);

  @override
  Stream<List<MoodLog>> watchRecent({int days = 14}) =>
      _db.watchRecentMoodLogs(days: days).map(
            (rows) => rows.map(_toDomain).toList(),
          );

  @override
  Future<void> log(MoodLog entry) => _db.insertMoodLog(
        MoodLogsCompanion(
          id: Value(entry.id),
          level: Value(entry.level.score),
          note: Value(entry.note),
          loggedAt: Value(entry.loggedAt),
        ),
      );

  MoodLog? _toDomainNullable(MoodLogRow? row) {
    if (row == null) return null;
    return _toDomain(row);
  }

  MoodLog _toDomain(MoodLogRow row) => MoodLog(
        id: row.id,
        level: MoodLevelX.fromScore(row.level),
        note: row.note,
        loggedAt: row.loggedAt,
      );
}
