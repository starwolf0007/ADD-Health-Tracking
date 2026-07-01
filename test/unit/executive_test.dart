// test/unit/executive_test.dart
//
// Unit tests for the Executive layer — pure Dart, no Flutter, no mocks needed.
// Run with: dart test test/unit/executive_test.dart

import 'package:flutter_test/flutter_test.dart';
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
      final low  = _task('Quick reply',       EnergyLevel.low);
      final med  = _task('Review doc',        EnergyLevel.medium);
      final high = _task('Big presentation',  EnergyLevel.high);

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

  // ─── Quick Wins auto-mode (§QW) ───────────────────────────────────────────

  group('Quick Wins auto-mode', () {
    test('triggers when all tasks low-energy and count ≤ 3', () {
      final tasks = [
        _task('Reply to Slack',      EnergyLevel.low),
        _task('Archive emails',      EnergyLevel.low),
        _task('Mark yesterday done', EnergyLevel.low),
      ];
      final plan = executive.evaluate(tasks);
      expect(plan.mode, DayMode.quickWins);
      expect(plan.quickWins.length, 3);
    });

    test('does NOT trigger when count > 3, even if all low-energy', () {
      final tasks = List.generate(4, (i) => _task('Low $i', EnergyLevel.low));
      final plan = executive.evaluate(tasks);
      expect(plan.mode, DayMode.normal);
    });

    test('does NOT trigger when any task is medium-energy', () {
      final plan = executive.evaluate([
        _task('Low task',    EnergyLevel.low),
        _task('Medium task', EnergyLevel.medium),
      ]);
      expect(plan.mode, DayMode.normal);
    });

    test('does NOT trigger when any task is high-energy', () {
      final plan = executive.evaluate([
        _task('Low task',  EnergyLevel.low),
        _task('High task', EnergyLevel.high),
      ]);
      expect(plan.mode, DayMode.normal);
    });

    test('quick wins list contains all input tasks', () {
      final tasks = [
        _task('A', EnergyLevel.low),
        _task('B', EnergyLevel.low),
      ];
      final plan = executive.evaluate(tasks);
      expect(plan.mode, DayMode.quickWins);
      expect(
        plan.quickWins.map((t) => t.id).toSet(),
        tasks.map((t) => t.id).toSet(),
      );
    });

    test('has a non-empty reason in Quick Wins mode', () {
      final plan = executive.evaluate([_task('Quick task', EnergyLevel.low)]);
      expect(plan.reason, isNotEmpty);
    });
  });
}

// Helpers
Task _task(String title, EnergyLevel energy) =>
    Task.create(title: title, energy: energy);
