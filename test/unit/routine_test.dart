// test/unit/routine_test.dart
//
// Unit tests for Routine domain model helpers.
// Run with: dart test test/unit/routine_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/routine.dart';

void main() {
  // ─── activeStep ───────────────────────────────────────────────────────────

  group('activeStep', () {
    test('returns null when no steps', () {
      expect(_routine([]).activeStep, isNull);
    });

    test('returns null when all steps complete', () {
      final r = _routine([_step(0, done: true), _step(1, done: true)]);
      expect(r.activeStep, isNull);
    });

    test('returns first incomplete step by position', () {
      final r = _routine([
        _step(0, done: true),
        _step(1, done: false),
        _step(2, done: false),
      ]);
      expect(r.activeStep?.position, 1);
    });

    test('position ordering holds regardless of list order', () {
      final r = _routine([
        _step(2, done: false),
        _step(0, done: true),
        _step(1, done: false),
      ]);
      expect(r.activeStep?.position, 1);
    });
  });

  // ─── isComplete ───────────────────────────────────────────────────────────

  group('isComplete', () {
    test('false when no steps', () {
      expect(_routine([]).isComplete, isFalse);
    });

    test('false when some steps incomplete', () {
      final r = _routine([_step(0, done: true), _step(1, done: false)]);
      expect(r.isComplete, isFalse);
    });

    test('true when all steps done', () {
      final r = _routine([_step(0, done: true), _step(1, done: true)]);
      expect(r.isComplete, isTrue);
    });
  });

  // ─── progressFraction ─────────────────────────────────────────────────────

  group('progressFraction', () {
    test('0.0 when no steps', () {
      expect(_routine([]).progressFraction, 0.0);
    });

    test('0.0 when nothing done', () {
      final r = _routine([_step(0), _step(1), _step(2)]);
      expect(r.progressFraction, 0.0);
    });

    test('0.5 when half done', () {
      final r = _routine([_step(0, done: true), _step(1, done: false)]);
      expect(r.progressFraction, 0.5);
    });

    test('1.0 when all done', () {
      final r = _routine([_step(0, done: true), _step(1, done: true)]);
      expect(r.progressFraction, 1.0);
    });
  });

  // ─── completedCount ───────────────────────────────────────────────────────

  group('completedCount', () {
    test('0 with no steps', () {
      expect(_routine([]).completedCount, 0);
    });

    test('counts only completed steps', () {
      final r = _routine([
        _step(0, done: true),
        _step(1, done: false),
        _step(2, done: true),
      ]);
      expect(r.completedCount, 2);
    });
  });

  // ─── firesOn ────────────────────────────────────────────────────────────────
  group('firesOn', () {
    // 2024-01-01 is a Monday; 2024-01-06 is a Saturday.
    final monday = DateTime(2024, 1, 1);
    final saturday = DateTime(2024, 1, 6);

    test('fires every day when activeDays is null', () {
      final r = _routine([]);
      expect(r.firesOn(monday), isTrue);
      expect(r.firesOn(saturday), isTrue);
    });

    test('fires every day when activeDays is empty', () {
      final r = _routine([], activeDays: '');
      expect(r.firesOn(monday), isTrue);
      expect(r.firesOn(saturday), isTrue);
    });

    test('fires only on listed weekdays', () {
      final weekdaysOnly = _routine([], activeDays: '12345');
      expect(weekdaysOnly.firesOn(monday), isTrue);
      expect(weekdaysOnly.firesOn(saturday), isFalse);
    });

    test('fires only on listed weekends', () {
      final weekendsOnly = _routine([], activeDays: '67');
      expect(weekendsOnly.firesOn(monday), isFalse);
      expect(weekendsOnly.firesOn(saturday), isTrue);
    });
  });

  // ─── Routine.create / copyWith ──────────────────────────────────────────────
  group('Routine.create', () {
    test('sets defaults and generates an id', () {
      final r = Routine.create(name: 'Morning', anchor: RoutineAnchor.morning);
      expect(r.name, 'Morning');
      expect(r.anchor, RoutineAnchor.morning);
      expect(r.isActive, isTrue);
      expect(r.steps, isEmpty);
      expect(r.id, isNotEmpty);
    });
  });

  group('Routine.copyWith', () {
    test('preserves id/createdAt and overrides given fields', () {
      final r = Routine.create(name: 'Morning', anchor: RoutineAnchor.morning);
      final updated = r.copyWith(name: 'Evening', anchor: RoutineAnchor.evening);
      expect(updated.id, r.id);
      expect(updated.createdAt, r.createdAt);
      expect(updated.name, 'Evening');
      expect(updated.anchor, RoutineAnchor.evening);
    });
  });

  // ─── RoutineStep.create / copyWith ──────────────────────────────────────────
  group('RoutineStep.create', () {
    test('sets fields and defaults to incomplete', () {
      final s = RoutineStep.create(
        routineId: 'r1',
        position: 2,
        title: 'Brush teeth',
        durationMinutes: 3,
      );
      expect(s.routineId, 'r1');
      expect(s.position, 2);
      expect(s.title, 'Brush teeth');
      expect(s.durationMinutes, 3);
      expect(s.isComplete, isFalse);
      expect(s.id, isNotEmpty);
    });
  });

  group('RoutineStep.copyWith', () {
    test('preserves id/routineId and overrides given fields', () {
      final s = RoutineStep.create(
        routineId: 'r1',
        position: 0,
        title: 'Old',
      );
      final updated = s.copyWith(title: 'New', isComplete: true, position: 5);
      expect(updated.id, s.id);
      expect(updated.routineId, s.routineId);
      expect(updated.title, 'New');
      expect(updated.isComplete, isTrue);
      expect(updated.position, 5);
    });
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────

Routine _routine(List<RoutineStep> steps, {String? activeDays}) {
  return Routine(
    id: 'test-routine',
    name: 'Test Routine',
    anchor: RoutineAnchor.morning,
    activeDays: activeDays,
    steps: steps,
    createdAt: DateTime.now(),
  );
}

RoutineStep _step(int position, {bool done = false}) {
  return RoutineStep(
    id: 'step-$position',
    routineId: 'test-routine',
    position: position,
    title: 'Step $position',
    isComplete: done,
  );
}
