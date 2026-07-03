// lib/data/note_repository.dart
//
// Interface + Drift implementation for Notes (v2 capture hub).
// Kept in one file for the drop-in; split to match repo convention if
// preferred — the classes are already independent.

import 'package:drift/drift.dart';

import '../domain/note.dart';
import 'database.dart';

abstract class NoteRepository {
  Stream<List<Note>> watchAll();
  Future<void> save(Note note);
  Future<void> delete(String id);
}

class DriftNoteRepository implements NoteRepository {
  final AppDatabase _db;

  DriftNoteRepository(this._db);

  Note _rowToNote(NoteRow row) => Note(
        id: row.id,
        body: row.body,
        pinned: row.pinned,
        linkedTaskId: row.linkedTaskId,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );

  NotesCompanion _noteToCompanion(Note n) => NotesCompanion(
        id: Value(n.id),
        body: Value(n.body),
        pinned: Value(n.pinned),
        linkedTaskId: Value(n.linkedTaskId),
        createdAt: Value(n.createdAt),
        updatedAt: Value(n.updatedAt),
      );

  @override
  Stream<List<Note>> watchAll() =>
      _db.watchNotes().map((rows) => rows.map(_rowToNote).toList());

  @override
  Future<void> save(Note note) => _db.upsertNote(_noteToCompanion(note));

  @override
  Future<void> delete(String id) => _db.deleteNote(id);
}
