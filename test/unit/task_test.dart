// test/unit/task_test.dart
//
// Unit tests for the Task domain model — pure Dart, no Flutter/Drift.
// Covers Task.create defaults, copyWith field propagation, and the
// isPending/isCompleted status helpers. The executive tests only exercise
// Task.create indirectly, so these fill the gaps in this module.
// Run with: dart test test/unit/task_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/task.dart';

void main() {
  // ─── create ──────────────────────────────────────────────────────────────
  group('Task.create', () {
    test('applies sensible defaults', () {
      final task = Task.create(title: 'Write report');
      expect(task.title, 'Write report');
      expect(task.energy, EnergyLevel.medium);
      expect(task.status, TaskStatus.pending);
      expect(task.notes, isNull);
      expect(task.dueDate, isNull);
      expect(task.isQuickWin, isFalse);
      expect(task.id, isNotEmpty);
    });

    test('honours explicit values', () {
      final due = DateTime(2030, 1, 1);
      final task = Task.create(
        title: 'Big task',
        notes: 'context',
        energy: EnergyLevel.high,
        dueDate: due,
        isQuickWin: true,
      );
      expect(task.notes, 'context');
      expect(task.energy, EnergyLevel.high);
      expect(task.dueDate, due);
      expect(task.isQuickWin, isTrue);
    });

    test('generates a distinct id per call', () {
      expect(Task.create(title: 'a').id, isNot(Task.create(title: 'b').id));
    });
  });

  // ─── status helpers ────────────────────────────────────────────────────────
  group('status helpers', () {
    test('a freshly created task is pending, not completed', () {
      final task = Task.create(title: 'New');
      expect(task.isPending, isTrue);
      expect(task.isCompleted, isFalse);
    });

    test('isCompleted is true only for completed status', () {
      final task = Task.create(title: 'Done')
          .copyWith(status: TaskStatus.completed);
      expect(task.isCompleted, isTrue);
      expect(task.isPending, isFalse);
    });

    test('non-pending, non-completed statuses report false for both', () {
      for (final status in [
        TaskStatus.skipped,
        TaskStatus.paused,
        TaskStatus.blocked,
      ]) {
        final task = Task.create(title: 's').copyWith(status: status);
        expect(task.isPending, isFalse, reason: 'status=$status');
        expect(task.isCompleted, isFalse, reason: 'status=$status');
      }
    });
  });

  // ─── copyWith ──────────────────────────────────────────────────────────────
  group('copyWith', () {
    test('preserves id and createdAt', () {
      final task = Task.create(title: 'Original');
      final updated = task.copyWith(title: 'Renamed');
      expect(updated.id, task.id);
      expect(updated.createdAt, task.createdAt);
      expect(updated.title, 'Renamed');
    });

    test('overrides only the provided fields', () {
      final task = Task.create(title: 'Keep', energy: EnergyLevel.low);
      final updated = task.copyWith(
        status: TaskStatus.completed,
        isQuickWin: true,
      );
      expect(updated.title, 'Keep');
      expect(updated.energy, EnergyLevel.low);
      expect(updated.status, TaskStatus.completed);
      expect(updated.isQuickWin, isTrue);
    });

    test('returns an equivalent task when no arguments given', () {
      final task = Task.create(title: 'Same', notes: 'n');
      final copy = task.copyWith();
      expect(copy.id, task.id);
      expect(copy.title, task.title);
      expect(copy.notes, task.notes);
      expect(copy.energy, task.energy);
      expect(copy.status, task.status);
      expect(copy.isQuickWin, task.isQuickWin);
    });
  });
}
