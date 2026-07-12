// lib/presentation/widgets/capture_sheet.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/presentation/theme.dart';

Future<void> showCaptureSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _CaptureSheetBody(),
  );
}

/// Opens the same focused editing controls used by the Today timeline.
/// A task without a scheduled time remains a flexible block.
Future<void> showTaskEditSheet(BuildContext context, Task task) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TaskEditSheetBody(task: task),
  );
}

class _CaptureSheetBody extends ConsumerStatefulWidget {
  const _CaptureSheetBody();

  @override
  ConsumerState<_CaptureSheetBody> createState() => _CaptureSheetBodyState();
}

class _CaptureSheetBodyState extends ConsumerState<_CaptureSheetBody> {
  final _controller = TextEditingController();
  EnergyLevel _energy = EnergyLevel.medium;
  final bool _quickWin = false;
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _submitting) return;
    setState(() => _submitting = true);

    final task = Task.create(
      title: title,
      energy: _energy,
      isQuickWin: _quickWin || _energy == EnergyLevel.low,
    );
    final repository = ref.read(taskRepositoryProvider);
    try {
      await repository.save(task).timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // A queued mirror-sync write can be delayed even after the local task
      // has committed. Confirm local persistence before treating it as a
      // failure so Capture never remains stuck on "Adding…".
      if (await repository.getById(task.id) == null) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not add task. Try again.')),
        );
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add task. Try again.')),
      );
      return;
    }

    // The Today providers currently consume the first Drift emission rather
    // than maintaining a live subscription, so refresh them after capture.
    ref.invalidate(todayControllerProvider);
    ref.invalidate(todayTimelineProvider);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Captured'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        MediaQuery.of(context).viewInsets.bottom + AppSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grab handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpace.lg),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => _submit(),
            style: AppTextStyles.bodyMedium.copyWith(fontSize: 17),
            decoration: const InputDecoration(
              hintText: "What's on your mind?",
              border: InputBorder.none,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const Text('ENERGY TO START', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.sm),
          Row(
            children: EnergyLevel.values.map((e) {
              final selected = e == _energy;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: ChoiceChip(
                  label: Text(e.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _energy = e),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpace.lg),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: Text(_submitting ? 'Adding…' : 'Add to today'),
          ),
        ],
      ),
    );
  }
}

class _TaskEditSheetBody extends ConsumerStatefulWidget {
  final Task task;

  const _TaskEditSheetBody({required this.task});

  @override
  ConsumerState<_TaskEditSheetBody> createState() => _TaskEditSheetBodyState();
}

class _TaskEditSheetBodyState extends ConsumerState<_TaskEditSheetBody> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late EnergyLevel _energy;
  DateTime? _scheduledAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _notesController = TextEditingController(text: widget.task.notes ?? '');
    _energy = widget.task.energy;
    _scheduledAt = widget.task.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickScheduledTime() async {
    final initial = _scheduledAt ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty || _saving) return;
    setState(() => _saving = true);

    final notes = _notesController.text.trim();
    final updated = Task(
      id: widget.task.id,
      title: title,
      notes: notes.isEmpty ? null : notes,
      energy: _energy,
      status: widget.task.status,
      createdAt: widget.task.createdAt,
      dueDate: _scheduledAt,
      completedAt: widget.task.completedAt,
      activeStartedAt: widget.task.activeStartedAt,
      estimatedMinutes: widget.task.estimatedMinutes,
      reentryNote: widget.task.reentryNote,
      isQuickWin: widget.task.isQuickWin,
    );

    try {
      await ref.read(taskRepositoryProvider).save(updated);
      ref.invalidate(todayControllerProvider);
      ref.invalidate(todayTimelineProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timeline item updated')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update task. Try again.')),
      );
    }
  }

  String _timeLabel(BuildContext context) {
    final value = _scheduledAt;
    if (value == null) return 'Flexible — no fixed time';
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatShortDate(value)} at '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(value))}';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Edit timeline item',
                        style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppSpace.lg),
                    TextField(
                      key: const ValueKey('task-editor-title'),
                      controller: _titleController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(labelText: 'Task name'),
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _notesController,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Optional)',
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    ListTile(
                      key: const ValueKey('task-editor-time'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('Timeline time'),
                      subtitle: Text(_timeLabel(context)),
                      onTap: _pickScheduledTime,
                    ),
                    if (_scheduledAt != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('task-editor-clear-time'),
                          onPressed: () => setState(() => _scheduledAt = null),
                          icon: const Icon(Icons.schedule_outlined),
                          label: const Text('Make flexible'),
                        ),
                      ),
                    const SizedBox(height: AppSpace.sm),
                    const Text('ENERGY TO START', style: AppTextStyles.label),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      children: EnergyLevel.values
                          .map(
                            (energy) => ChoiceChip(
                              label: Text(energy.name),
                              selected: _energy == energy,
                              onSelected: (_) =>
                                  setState(() => _energy = energy),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            FilledButton(
              key: const ValueKey('task-editor-save'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
