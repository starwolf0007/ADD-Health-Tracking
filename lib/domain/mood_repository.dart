// lib/domain/mood_repository.dart
//
// Abstract repository interface for the mood check-in. Pure Dart — no Flutter,
// no Drift, no Riverpod. The Drift implementation is injected at the
// composition root (see app/providers.dart).
//
// §2.8 HARD RULE: mood data is on-device only. This contract deliberately has
// no sync, push, or export method — do not add one.

import 'package:neuroflow/domain/mood.dart';

abstract class MoodRepository {
  /// The most recent check-in logged today, or null if none has been logged.
  ///
  /// "Today" is the boundary that matters: §6 exits Quick Wins when the day
  /// rolls over, so yesterday's rough check-in must not reshape this morning.
  Stream<MoodLog?> watchTodayLatest();

  /// Recent check-ins newest first (default last 14 days). For Reflect history.
  Stream<List<MoodLog>> watchRecent({int days = 14});

  Future<void> log(MoodLog entry);
}
