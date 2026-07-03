// lib/domain/mood.dart
//
// Pure domain model — no Flutter, no Drift, no Riverpod.
//
// The 5-point mood check-in is the REAL Quick Wins trigger (spec §6):
// a check-in at `low` or below flips Today into Quick Wins mode for the
// rest of the day, until a better check-in lands.
//
// §2.8 HARD RULE: mood data is on-device only. It never syncs, never
// mirrors, never reaches any cloud advisor. The MoodLogs table has no
// sync columns BY DESIGN — do not add them.

import 'package:uuid/uuid.dart';

enum MoodLevel { veryLow, low, neutral, good, great }

extension MoodLevelX on MoodLevel {
  /// 1..5 for storage — never shown to the user as a score (§13: no
  /// visible numeric self-judgment).
  int get score => index + 1;

  String get label => switch (this) {
        MoodLevel.veryLow => 'Rough',
        MoodLevel.low => 'Low',
        MoodLevel.neutral => 'Okay',
        MoodLevel.good => 'Good',
        MoodLevel.great => 'Great',
      };

  static MoodLevel fromScore(int score) =>
      MoodLevel.values[(score - 1).clamp(0, MoodLevel.values.length - 1)];

  /// The Quick Wins threshold: low or below reshapes Today.
  bool get triggersQuickWins => index <= MoodLevel.low.index;
}

class MoodLog {
  final String id;
  final MoodLevel level;
  final String? note;
  final DateTime loggedAt;

  const MoodLog({
    required this.id,
    required this.level,
    this.note,
    required this.loggedAt,
  });

  factory MoodLog.create(MoodLevel level, {String? note}) {
    return MoodLog(
      id: const Uuid().v4(),
      level: level,
      note: note,
      loggedAt: DateTime.now(),
    );
  }
}
