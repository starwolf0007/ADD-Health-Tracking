// lib/presentation/notes_screen.dart
//
// The Notes tab (v2). Capture has to cost nothing: one field at the top,
// submit keeps focus so thoughts can land back-to-back. Each note can be
// pinned, swiped away, or promoted into a Task in one tap — promote = move,
// with a snackbar receipt ("Added to Today").

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/note.dart';
import '../domain/task.dart';
import 'theme.dart';

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    HapticFeedback.selectionClick();
    _controller.clear();
    await ref.read(noteRepositoryProvider).save(Note.create(body));
    if (mounted) _focusNode.requestFocus(); // capture stays open for the next thought
  }

  Future<void> _promote(Note note) async {
    HapticFeedback.lightImpact();
    final task = Task.create(
      title: note.firstLine.isEmpty ? note.body : note.firstLine,
      notes: note.rest,
    );
    await ref.read(taskRepositoryProvider).save(task);
    await ref.read(noteRepositoryProvider).delete(note.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Added to Today')));
  }

  Future<void> _togglePin(Note note) async {
    HapticFeedback.selectionClick();
    await ref
        .read(noteRepositoryProvider)
        .save(note.copyWith(pinned: !note.pinned));
  }

  Future<void> _delete(Note note) =>
      ref.read(noteRepositoryProvider).delete(note.id);

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notes'), centerTitle: false),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.md),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              style: AppTextStyles.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Catch a thought…',
                suffixIcon: IconButton(
                  onPressed: _add,
                  icon: const Icon(Icons.arrow_upward_rounded),
                  color: AppColors.accent,
                  tooltip: 'Save note',
                ),
              ),
            ),
          ),
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              ),
              error: (e, _) => const Center(
                child: Text('Notes are unavailable right now.',
                    style: AppTextStyles.bodyMedium),
              ),
              data: (notes) {
                if (notes.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpace.xl),
                      child: Text(
                        'Nothing here yet.\nAnything you type above lands '
                        'instantly — sort it out later, or never.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.xl, 0, AppSpace.xl, AppSpace.xxl),
                  itemCount: notes.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpace.md),
                  itemBuilder: (context, i) => _NoteCard(
                    note: notes[i],
                    onPromote: () => _promote(notes[i]),
                    onPin: () => _togglePin(notes[i]),
                    onDelete: () => _delete(notes[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onPromote;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  const _NoteCard({
    required this.note,
    required this.onPromote,
    required this.onPin,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpace.xl),
        decoration: BoxDecoration(
          color: AppColors.attentionWash,
          borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        ),
        child: const Icon(Icons.delete_outline,
            color: AppColors.attention, size: 22),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.lg, AppSpace.sm, AppSpace.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium,
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(_ago(note.updatedAt), style: AppTextStyles.bodySmall),
                ],
              ),
            ),
            IconButton(
              onPressed: onPin,
              icon: Icon(
                note.pinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 20,
              ),
              color:
                  note.pinned ? AppColors.accent : AppColors.textMuted,
              tooltip: note.pinned ? 'Unpin' : 'Pin',
            ),
            IconButton(
              onPressed: onPromote,
              icon: const Icon(Icons.add_task, size: 20),
              color: AppColors.accent,
              tooltip: 'Make it a task',
            ),
          ],
        ),
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
