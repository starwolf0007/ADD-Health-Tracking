// test/unit/mood_test.dart
//
// Unit tests for the Mood domain model — pure Dart, no Flutter/Drift.
// Covers the MoodLevelX extension (score/label/fromScore/triggersQuickWins)
// and MoodLog.create. Previously this module had no test coverage.
// Run with: dart test test/unit/mood_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/mood.dart';

void main() {
  // ─── score ─────────────────────────────────────────────────────────────
  group('MoodLevelX.score', () {
    test('maps each level to 1..5 in declaration order', () {
      expect(MoodLevel.veryLow.score, 1);
      expect(MoodLevel.low.score, 2);
      expect(MoodLevel.neutral.score, 3);
      expect(MoodLevel.good.score, 4);
      expect(MoodLevel.great.score, 5);
    });

    test('score is always index + 1 for every value', () {
      for (final level in MoodLevel.values) {
        expect(level.score, level.index + 1);
      }
    });
  });

  // ─── label ─────────────────────────────────────────────────────────────
  group('MoodLevelX.label', () {
    test('returns the human-facing word for each level', () {
      expect(MoodLevel.veryLow.label, 'Rough');
      expect(MoodLevel.low.label, 'Low');
      expect(MoodLevel.neutral.label, 'Okay');
      expect(MoodLevel.good.label, 'Good');
      expect(MoodLevel.great.label, 'Great');
    });

    test('every level has a non-empty label', () {
      for (final level in MoodLevel.values) {
        expect(level.label, isNotEmpty);
      }
    });
  });

  // ─── fromScore ──────────────────────────────────────────────────────────
  group('MoodLevelX.fromScore', () {
    test('round-trips score -> level for valid scores', () {
      for (final level in MoodLevel.values) {
        expect(MoodLevelX.fromScore(level.score), level);
      }
    });

    test('clamps scores below 1 to veryLow', () {
      expect(MoodLevelX.fromScore(0), MoodLevel.veryLow);
      expect(MoodLevelX.fromScore(-5), MoodLevel.veryLow);
    });

    test('clamps scores above 5 to great', () {
      expect(MoodLevelX.fromScore(6), MoodLevel.great);
      expect(MoodLevelX.fromScore(99), MoodLevel.great);
    });
  });

  // ─── triggersQuickWins ────────────────────────────────────────────────────
  group('MoodLevelX.triggersQuickWins', () {
    test('is true at low and below', () {
      expect(MoodLevel.veryLow.triggersQuickWins, isTrue);
      expect(MoodLevel.low.triggersQuickWins, isTrue);
    });

    test('is false at neutral and above', () {
      expect(MoodLevel.neutral.triggersQuickWins, isFalse);
      expect(MoodLevel.good.triggersQuickWins, isFalse);
      expect(MoodLevel.great.triggersQuickWins, isFalse);
    });
  });

  // ─── MoodLog.create ──────────────────────────────────────────────────────
  group('MoodLog.create', () {
    test('populates level and generates a non-empty id', () {
      final log = MoodLog.create(MoodLevel.good);
      expect(log.level, MoodLevel.good);
      expect(log.id, isNotEmpty);
      expect(log.note, isNull);
    });

    test('keeps the optional note when provided', () {
      final log = MoodLog.create(MoodLevel.low, note: 'tired');
      expect(log.note, 'tired');
    });

    test('stamps loggedAt at roughly now', () {
      final before = DateTime.now();
      final log = MoodLog.create(MoodLevel.great);
      final after = DateTime.now();
      expect(log.loggedAt.isBefore(before.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(log.loggedAt.isAfter(after.add(const Duration(seconds: 1))),
          isFalse);
    });

    test('generates a distinct id per call', () {
      final a = MoodLog.create(MoodLevel.neutral);
      final b = MoodLog.create(MoodLevel.neutral);
      expect(a.id, isNot(b.id));
    });
  });
}
