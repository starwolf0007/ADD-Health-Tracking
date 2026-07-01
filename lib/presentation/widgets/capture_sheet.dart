// lib/presentation/widgets/capture_sheet.dart
//
// PRESENTATION LAYER. The realization of §13's "capture reachable from
// anywhere in one gesture" rule: one input, one "Add to inbox" button,
// nothing else. Opened from a persistent affordance on every screen (Today's
// FAB today; the same sheet should be reachable identically from any future
// screen — don't fork this per-screen).
//
// PHASE NOTE: the local NLP parser (date/time/list extraction from the typed
// sentence, §5 Rail 1) is phase 2. This sheet creates a plain Task with the
// raw title and no due date for now — capture still works end-to-end, it
// just doesn't self-schedule yet. Swapping in the parser later only touches
// _submit() below; the sheet/UI doesn't change.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/providers.dart';
import '../../domain/task.dart';
import '../theme.dart';

Future<void> showCaptureSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (ctx) => const _CaptureSheetBody(),
  );
}

class _CaptureSheetBody extends ConsumerStatefulWidget {
  const _CaptureSheetBody();

  @override
  ConsumerState<_CaptureSheetBody> createState() => _CaptureSheetBodyState();
}

class _CaptureSheetBodyState extends ConsumerState<_CaptureSheetBody> {
  final _controller = TextEditingController();
  bool _submitting = false;

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _submitting) return;
    setState(() => _submitting = true);

    final now = DateTime.now();
    final task = Task(
      id: const Uuid().v4(),
      title: title,
      source: TaskSource.quickAdd,
      // TODO(phase 2): run the local chrono-style parser on `title` here and
      // populate `due` — the one line this whole sheet exists to make easy.
      createdAt: now,
      lastTouchedAt: now,
      updatedAt: now,
    );

    await ref.read(taskRepositoryProvider).save(task);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17),
            decoration: const InputDecoration(
              hintText: "What's on your mind?",
              hintStyle: TextStyle(color: AppColors.textFaint),
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? "Adding…" : "Add to inbox"),
          ),
        ],
      ),
    );
  }
}
