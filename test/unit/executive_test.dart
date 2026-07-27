// test/unit/executive_test.dart
//
// Unit tests for the Executive layer — pure Dart, no Flutter, no mocks needed.
// Run with: dart test test/unit/executive_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/mood.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/executive/planner.dart';

void main() {
  late Executive executive;

  setUp(() {
    executive = Executive();
  });

  // ─── Empty list ───────────────────────────────────────────────────────────

  group('empty pending list', () {
    test('returns normal mode with no primary task', () {
      final plan = executive.evaluate([]);
      expect(plan.mode, DayMode.normal);
      expect(plan.primaryTask, isNull);
      expect(plan.quickWins, isEmpty);
    });

    test('reason is non-empty', () {
      final plan = executive.evaluate([]);
      expect(plan.reason, isNotEmpty);
    });
  });

  // ─── Normal mode — single task ────────────────────────────────────────────

  group('single task', () {
    test('surfaces that task as primary', () {
      final task = _task('Write report', EnergyLevel.high);
      final plan = executive.evaluate([task]);
      expect(plan.mode, DayMode.normal);
      expect(plan.primaryTask?.id, task.id);
    });

    test('does NOT enter Quick Wins mode for a single high-energy task', () {
      final task = _task('Big presentation', EnergyLevel.high);
      final plan = executive.evaluate([task]);
      expect(plan.mode, DayMode.normal);
    });
  });

  // ─── Priority ordering ────────────────────────────────────────────────────

  group('priority ordering', () {
    test('surfaces lowest-energy task first', () {
      final low = _task('Quick reply', EnergyLevel.low);
      final med = _task('Review doc', EnergyLevel.medium);
      final high = _task('Big presentation', EnergyLevel.high);

      final plan = executive.evaluate([high, med, low]);
      expect(plan.primaryTask?.id, low.id);
    });

    test('among equal-energy tasks picks one deterministically', () {
      final a = _task('Task A', EnergyLevel.medium);
      final b = _task('Task B', EnergyLevel.medium);
      final plan1 = executive.evaluate([a, b]);
      final plan2 = executive.evaluate([a, b]);
      expect(plan1.primaryTask?.id, plan2.primaryTask?.id);
    });
  });

  // ─── Quick Wins entry — user state, never list shape (§6) ─────────────────
  //
  // These replace an earlier group that asserted the inverted behavior:
  // entering Quick Wins because every pending task happened to be low-energy
  // and there were ≤3 of them. Spec §6 enters the mode "automatically by
  // signal", and treats the low-energy filter as candidate selection only.
  // The old expectations are inverted below rather than deleted.

  group('Quick Wins entry', () {
    test('does NOT trigger from task composition alone', () {
      final tasks = [
        _task('Reply to Slack', EnergyLevel.low),
        _task('Archive emails', EnergyLevel.low),
        _task('Mark yesterday done', EnergyLevel.low),
      ];
      final plan = executive.evaluate(tasks);
      expect(plan.mode, DayMode.normal);
    });

    test('does NOT trigger when no capacity signal is available', () {
      final plan = executive.evaluate(
        [_task('Low task', EnergyLevel.low)],
        capacity: DayCapacity.unknown,
      );
      expect(plan.mode, DayMode.normal);
    });

    test('triggers on a rough mood check-in', () {
      final plan = executive.evaluate(
        [_task('Big presentation', EnergyLevel.high)],
        capacity: const DayCapacity(latestMood: MoodLevel.veryLow),
      );
      expect(plan.mode, DayMode.quickWins);
    });

    test('triggers on a low mood check-in', () {
      final plan = executive.evaluate(
        [_task('Big presentation', EnergyLevel.high)],
        capacity: const DayCapacity(latestMood: MoodLevel.low),
      );
      expect(plan.mode, DayMode.quickWins);
    });

    test('does NOT trigger once the mood lifts', () {
      const liftedMoods = [
        MoodLevel.neutral,
        MoodLevel.good,
        MoodLevel.great,
      ];
      for (final mood in liftedMoods) {
        final plan = executive.evaluate(
          [_task('Low task', EnergyLevel.low)],
          capacity: DayCapacity(latestMood: mood),
        );
        expect(plan.mode, DayMode.normal, reason: 'mood: $mood');
      }
    });

    test('triggers on a heavy day — the day it is most needed', () {
      final tasks = List.generate(8, (i) => _task('Big $i', EnergyLevel.high));
      final plan = executive.evaluate(
        tasks,
        capacity: const DayCapacity(latestMood: MoodLevel.veryLow),
      );
      expect(plan.mode, DayMode.quickWins);
    });

    test('stays normal on an empty list even when the mood is rough', () {
      final plan = executive.evaluate(
        [],
        capacity: const DayCapacity(latestMood: MoodLevel.veryLow),
      );
      expect(plan.mode, DayMode.normal);
      expect(plan.quickWins, isEmpty);
    });

    test('has a non-empty reason in Quick Wins mode', () {
      final plan = executive.evaluate(
        [_task('Quick task', EnergyLevel.low)],
        capacity: const DayCapacity(latestMood: MoodLevel.low),
      );
      expect(plan.reason, isNotEmpty);
    });
  });

  // ─── Quick Wins selection — what the reshaped Today shows (§6) ────────────

  group('Quick Wins selection', () {
    test('caps the list at three', () {
      final tasks = List.generate(7, (i) => _task('Low $i', EnergyLevel.low));
      final plan = executive.evaluate(
        tasks,
        capacity: const DayCapacity(latestMood: MoodLevel.low),
      );
      expect(plan.quickWins.length, 3);
    });

    test('prefers low-energy candidates', () {
      final low = _task('Quick reply', EnergyLevel.low);
      final high = _task('Big presentation', EnergyLevel.high);
      final plan = executive.evaluate(
        [high, low],
        capacity: const DayCapacity(latestMood: MoodLevel.low),
      );
      expect(plan.quickWins.map((t) => t.id), [low.id]);
    });

    test('orders by lowest estimated effort first', () {
      final long = _task('Long', EnergyLevel.low, estimatedMinutes: 45);
      final short = _task('Short', EnergyLevel.low, estimatedMinutes: 5);
      final middle = _task('Middle', EnergyLevel.low, estimatedMinutes: 20);

      final plan = executive.evaluate(
        [long, short, middle],
        capacity: const DayCapacity(latestMood: MoodLevel.low),
      );
      expect(
        plan.quickWins.map((t) => t.title),
        ['Short', 'Middle', 'Long'],
      );
    });

    test('sorts tasks with no estimate last', () {
      final unknown = _task('No estimate', EnergyLevel.low);
      final known = _task('Estimated', EnergyLevel.low, estimatedMinutes: 30);

      final plan = executive.evaluate(
        [unknown, known],
        capacity: const DayCapacity(latestMood: MoodLevel.low),
      );
      expect(plan.quickWins.map((t) => t.title), ['Estimated', 'No estimate']);
    });

    test('still contains the day when nothing qualifies on energy', () {
      final tasks = List.generate(5, (i) => _task('Big $i', EnergyLevel.high));
      final plan = executive.evaluate(
        tasks,
        capacity: const DayCapacity(latestMood: MoodLevel.veryLow),
      );
      expect(plan.mode, DayMode.quickWins);
      expect(plan.quickWins.length, 3);
    });

    test('is stable across repeated evaluations', () {
      final tasks = [
        _task('A', EnergyLevel.low),
        _task('B', EnergyLevel.low),
        _task('C', EnergyLevel.low),
        _task('D', EnergyLevel.low),
      ];
      const capacity = DayCapacity(latestMood: MoodLevel.low);
      final first = executive.evaluate(tasks, capacity: capacity);
      final second = executive.evaluate(tasks, capacity: capacity);
      expect(
        first.quickWins.map((t) => t.id).toList(),
        second.quickWins.map((t) => t.id).toList(),
      );
    });
  });

  // ─── DayCapacity ──────────────────────────────────────────────────────────

  group('DayCapacity', () {
    test('unknown does not indicate a lighter day', () {
      expect(DayCapacity.unknown.indicatesLighterDay, isFalse);
    });

    test('mirrors the domain mood threshold', () {
      for (final mood in MoodLevel.values) {
        expect(
          DayCapacity(latestMood: mood).indicatesLighterDay,
          mood.triggersQuickWins,
          reason: 'mood: $mood',
        );
      }
    });
  });
}

// Helpers
Task _task(String title, EnergyLevel energy, {int? estimatedMinutes}) =>
    Task.create(
      title: title,
      energy: energy,
      estimatedMinutes: estimatedMinutes,
    );
