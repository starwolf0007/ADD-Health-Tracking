// test/unit/mood_repository_test.dart
//
// The mood check-in is the Quick Wins entry signal (spec §6), so the "today"
// boundary and the most-recent-wins rule are load-bearing, not incidental.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/data/mood_repository_impl.dart';
import 'package:neuroflow/domain/mood.dart';

void main() {
  late AppDatabase database;
  late DriftMoodRepository repository;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = DriftMoodRepository(database);
    addTearDown(database.close);
  });

  test('returns null when nothing has been logged', () async {
    expect(await repository.watchTodayLatest().first, isNull);
  });

  test('round-trips a logged check-in', () async {
    final entry = MoodLog.create(MoodLevel.low, note: 'rough morning');
    await repository.log(entry);

    final saved = await repository.watchTodayLatest().first;
    expect(saved, isNotNull);
    expect(saved!.id, entry.id);
    expect(saved.level, MoodLevel.low);
    expect(saved.note, 'rough morning');
  });

  test('preserves every mood level across the storage boundary', () async {
    // level is persisted as a 1..5 score; an off-by-one here would silently
    // change which days enter Quick Wins.
    for (final level in MoodLevel.values) {
      // Distinct, increasing times so "most recent" is unambiguous — equal
      // timestamps would make the ORDER BY ... LIMIT 1 result arbitrary.
      final entry = MoodLog(
        id: 'mood-${level.name}',
        level: level,
        loggedAt: _todayAt(8 + level.index),
      );
      await repository.log(entry);

      final saved = await repository.watchTodayLatest().first;
      expect(saved?.level, level, reason: 'level: $level');
    }
  });

  test('returns the most recent check-in of the day', () async {
    await repository.log(
      MoodLog(id: 'morning', level: MoodLevel.veryLow, loggedAt: _todayAt(8)),
    );
    await repository.log(
      MoodLog(id: 'afternoon', level: MoodLevel.good, loggedAt: _todayAt(15)),
    );

    final saved = await repository.watchTodayLatest().first;
    expect(saved?.id, 'afternoon');
    expect(saved?.level, MoodLevel.good);
  });

  test('ignores a check-in logged before today', () async {
    // §6 exits Quick Wins when the day rolls over — yesterday's rough
    // check-in must not reshape this morning.
    await repository.log(
      MoodLog(
        id: 'yesterday',
        level: MoodLevel.veryLow,
        loggedAt: _todayAt(9).subtract(const Duration(days: 1)),
      ),
    );

    expect(await repository.watchTodayLatest().first, isNull);
  });

  test('a null note round-trips as null', () async {
    await repository.log(MoodLog.create(MoodLevel.neutral));
    final saved = await repository.watchTodayLatest().first;
    expect(saved?.note, isNull);
  });
}

DateTime _todayAt(int hour) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour);
}
