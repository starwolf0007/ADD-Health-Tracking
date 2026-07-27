// lib/domain/note_repository.dart
//
// Abstract repository for Notes. Pure Dart — no Flutter, no Drift, no Riverpod.
// Implementation is injected at the composition root (app/providers.dart).
//
// Notes are local-first capture. Promote-to-task is a later concern of the
// presentation/controller layer; this contract stays focused on persistence.

import 'package:neuroflow/domain/note.dart';

abstract class NoteRepository {
  /// All notes, pinned first, then most recently updated.
  Stream<List<Note>> watchAll();

  Future<void> save(Note note);

  Future<void> delete(String id);
}
