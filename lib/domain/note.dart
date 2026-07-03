// lib/domain/note.dart
//
// Pure domain model — no Flutter, no Drift, no Riverpod.
//
// Notes are the low-friction capture surface: a thought lands here in one
// tap, and can later be promoted into a Task ("promote = move"). A note that
// became a task remembers nothing — the task carries the content forward.

import 'package:uuid/uuid.dart';

class Note {
  final String id;
  final String body;
  final bool pinned;
  final String? linkedTaskId; // set if this note was promoted (kept for undo)
  final DateTime createdAt;
  final DateTime updatedAt;

  const Note({
    required this.id,
    required this.body,
    this.pinned = false,
    this.linkedTaskId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Note.create(String body) {
    final now = DateTime.now();
    return Note(
      id: const Uuid().v4(),
      body: body,
      pinned: false,
      createdAt: now,
      updatedAt: now,
    );
  }

  Note copyWith({
    String? body,
    bool? pinned,
    String? linkedTaskId,
  }) {
    return Note(
      id: id,
      body: body ?? this.body,
      pinned: pinned ?? this.pinned,
      linkedTaskId: linkedTaskId ?? this.linkedTaskId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// First line of the body — used as the task title on promote.
  String get firstLine {
    final idx = body.indexOf('\n');
    return (idx == -1 ? body : body.substring(0, idx)).trim();
  }

  /// Everything after the first line — becomes the task's notes on promote.
  String? get rest {
    final idx = body.indexOf('\n');
    if (idx == -1) return null;
    final r = body.substring(idx + 1).trim();
    return r.isEmpty ? null : r;
  }
}
