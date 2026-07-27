// lib/data/note_repository_impl.dart
//
// Drift-backed NoteRepository. Local-only — notes do not enter the sync queue.

import 'package:drift/drift.dart';

import 'package:neuroflow/data/database.dart';
import 'package:neuroflow/domain/note.dart';
import 'package:neuroflow/domain/note_repository.dart';

class DriftNoteRepository implements NoteRepository {
  final AppDatabase _db;

  DriftNoteRepository(this._db);

  @override
  Stream<List<Note>> watchAll() =>
      _db.watchNotes().map((rows) => rows.map(_toDomain).toList());

  @override
  Future<void> save(Note note) => _db.upsertNote(
        NotesCompanion(
          id: Value(note.id),
          body: Value(note.body),
          pinned: Value(note.pinned),
          linkedTaskId: Value(note.linkedTaskId),
          createdAt: Value(note.createdAt),
          updatedAt: Value(note.updatedAt),
        ),
      );

  @override
  Future<void> delete(String id) => _db.deleteNote(id);

  Note _toDomain(NoteRow row) => Note(
        id: row.id,
        body: row.body,
        pinned: row.pinned,
        linkedTaskId: row.linkedTaskId,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
