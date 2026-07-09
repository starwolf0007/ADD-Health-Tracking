// test/unit/note_test.dart
//
// Unit tests for the Note domain model — pure Dart, no Flutter/Drift.
// Covers create, copyWith, and the firstLine/rest split used when a note is
// promoted into a Task. Previously this module had no test coverage.
// Run with: dart test test/unit/note_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/note.dart';

void main() {
  // ─── create ──────────────────────────────────────────────────────────────
  group('Note.create', () {
    test('sets body and defaults, generates an id', () {
      final note = Note.create('Buy milk');
      expect(note.body, 'Buy milk');
      expect(note.pinned, isFalse);
      expect(note.linkedTaskId, isNull);
      expect(note.id, isNotEmpty);
    });

    test('createdAt and updatedAt are equal at creation', () {
      final note = Note.create('Same timestamps');
      expect(note.createdAt, note.updatedAt);
    });

    test('generates a distinct id per call', () {
      expect(Note.create('a').id, isNot(Note.create('b').id));
    });
  });

  // ─── firstLine ───────────────────────────────────────────────────────────
  group('firstLine', () {
    test('returns the whole body when single-line', () {
      expect(Note.create('One liner').firstLine, 'One liner');
    });

    test('returns only the first line when multi-line', () {
      expect(Note.create('Title\nbody text').firstLine, 'Title');
    });

    test('trims surrounding whitespace', () {
      expect(Note.create('  padded  \nrest').firstLine, 'padded');
    });

    test('is empty when body is empty', () {
      expect(Note.create('').firstLine, isEmpty);
    });
  });

  // ─── rest ────────────────────────────────────────────────────────────────
  group('rest', () {
    test('is null when there is no newline', () {
      expect(Note.create('Only one line').rest, isNull);
    });

    test('returns everything after the first line', () {
      expect(Note.create('Title\nmore details').rest, 'more details');
    });

    test('joins and trims multiple trailing lines', () {
      expect(Note.create('Title\nline two\nline three').rest,
          'line two\nline three');
    });

    test('is null when the remainder is only whitespace', () {
      expect(Note.create('Title\n   \n  ').rest, isNull);
    });
  });

  // ─── copyWith ──────────────────────────────────────────────────────────────
  group('copyWith', () {
    test('preserves id and createdAt', () {
      final note = Note.create('Original');
      final updated = note.copyWith(body: 'Changed');
      expect(updated.id, note.id);
      expect(updated.createdAt, note.createdAt);
      expect(updated.body, 'Changed');
    });

    test('bumps updatedAt to at least the original', () {
      final note = Note.create('Original');
      final updated = note.copyWith(pinned: true);
      expect(updated.updatedAt.isBefore(note.updatedAt), isFalse);
      expect(updated.pinned, isTrue);
    });

    test('leaves untouched fields unchanged', () {
      final note = Note.create('Keep me');
      final updated = note.copyWith(linkedTaskId: 'task-1');
      expect(updated.body, 'Keep me');
      expect(updated.pinned, isFalse);
      expect(updated.linkedTaskId, 'task-1');
    });
  });
}
