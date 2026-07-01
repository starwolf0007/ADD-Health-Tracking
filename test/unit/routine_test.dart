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
}

// ─── Helpers ──────────────────────────────────────────────────────────────

Routine _routine(List<RoutineStep> steps) {
  return Routine(
    id: 'test-routine',
    name: 'Test Routine',
    anchor: RoutineAnchor.morning,
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
