// test/unit/lexi_config_test.dart
//
// Unit tests for LexiConfig — pure string-building, no Flutter/model deps.
// Covers the systemPrompt constant and buildRefinementPrompt formatting.
// Previously this module had no test coverage.
// Run with: dart test test/unit/lexi_config_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/intelligence/lexi_config.dart';

void main() {
  // ─── systemPrompt ──────────────────────────────────────────────────────────
  group('systemPrompt', () {
    test('is non-empty and introduces Lexi', () {
      expect(LexiConfig.systemPrompt, isNotEmpty);
      expect(LexiConfig.systemPrompt, contains('Lexi'));
    });
  });

  // ─── buildRefinementPrompt ─────────────────────────────────────────────────
  group('buildRefinementPrompt', () {
    test('includes the mode and total pending count', () {
      final prompt = LexiConfig.buildRefinementPrompt(
        mode: 'normal',
        primaryTaskTitle: null,
        quickWinTitles: const [],
        totalPending: 4,
      );
      expect(prompt, contains('Mode: normal'));
      expect(prompt, contains('Total pending: 4'));
    });

    test('includes the primary task line when a title is given', () {
      final prompt = LexiConfig.buildRefinementPrompt(
        mode: 'normal',
        primaryTaskTitle: 'Write report',
        quickWinTitles: const [],
        totalPending: 1,
      );
      expect(prompt, contains('Primary task: Write report'));
    });

    test('omits the primary task line when title is null', () {
      final prompt = LexiConfig.buildRefinementPrompt(
        mode: 'quickWins',
        primaryTaskTitle: null,
        quickWinTitles: const ['A', 'B'],
        totalPending: 2,
      );
      expect(prompt, isNot(contains('Primary task:')));
    });

    test('joins quick win titles with commas', () {
      final prompt = LexiConfig.buildRefinementPrompt(
        mode: 'quickWins',
        primaryTaskTitle: null,
        quickWinTitles: const ['Reply', 'Archive', 'Mark done'],
        totalPending: 3,
      );
      expect(prompt, contains('Quick wins: Reply, Archive, Mark done'));
    });

    test('omits the quick wins line when the list is empty', () {
      final prompt = LexiConfig.buildRefinementPrompt(
        mode: 'normal',
        primaryTaskTitle: 'Solo task',
        quickWinTitles: const [],
        totalPending: 1,
      );
      expect(prompt, isNot(contains('Quick wins:')));
    });

    test('always closes with the reason-line instruction', () {
      final prompt = LexiConfig.buildRefinementPrompt(
        mode: 'normal',
        primaryTaskTitle: 'x',
        quickWinTitles: const [],
        totalPending: 1,
      );
      expect(prompt, contains('{}'));
    });
  });
}
