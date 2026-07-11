// lib/presentation/routines_list_screen.dart
//
// The Routines tab. A quiet list of active routines.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/presentation/routine_screen.dart';
import 'package:neuroflow/presentation/theme.dart';

class RoutinesListScreen extends ConsumerWidget {
  const RoutinesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(activeRoutinesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        centerTitle: false,
      ),
      body: routinesAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.accent),
        ),
        error: (e, _) => const Center(child: Text('Error loading routines')),
        data: (routines) {
          if (routines.isEmpty) {
            return const Center(child: Text('No routines yet.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpace.xl),
            itemCount: routines.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpace.md),
            itemBuilder: (context, i) => _RoutineCard(routine: routines[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showRoutineScheduleSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add routine'),
      ),
    );
  }
}

Future<void> _showRoutineScheduleSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _RoutineScheduleSheet(),
  );
}

class _RoutineScheduleSheet extends ConsumerStatefulWidget {
  const _RoutineScheduleSheet();

  @override
  ConsumerState<_RoutineScheduleSheet> createState() =>
      _RoutineScheduleSheetState();
}

class _RoutineScheduleSheetState extends ConsumerState<_RoutineScheduleSheet> {
  final _nameController = TextEditingController();
  final _stepController = TextEditingController();
  final List<String> _steps = [];
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (_saving) return;
    final pendingStep = _stepController.text.trim();
    if (pendingStep.isNotEmpty) {
      _steps.add(pendingStep);
      _stepController.clear();
    }
    if (name.isEmpty || _steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add a routine name and at least one step.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final routine = Routine.create(
        name: name,
        anchor: RoutineAnchor.custom,
        scheduleHour: _time.hour,
        scheduleMinute: _time.minute,
      );
      final completeRoutine = routine.copyWith(
        steps: [
          for (var index = 0; index < _steps.length; index++)
            RoutineStep.create(
              routineId: routine.id,
              position: index,
              title: _steps[index],
            ),
        ],
      );
      await ref.read(routineRepositoryProvider).save(completeRoutine);
      ref.invalidate(activeRoutinesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('Could not save routine: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save routine. Try again.')),
      );
    }
  }

  Future<void> _pickTime() async {
    final selected = await showTimePicker(context: context, initialTime: _time);
    if (selected != null && mounted) setState(() => _time = selected);
  }

  void _addStep() {
    final title = _stepController.text.trim();
    if (title.isEmpty) return;
    setState(() {
      _steps.add(title);
      _stepController.clear();
    });
  }

  void _addWorkPrepStarter() {
    setState(() {
      for (final step in const [
        'Brush teeth',
        'Make bed',
        'Take medicine',
        'Grab wallet, watch, and keys',
        'Leave for work by 5:45 AM',
      ]) {
        if (!_steps.contains(step)) _steps.add(step);
      }
    });
  }

  void _moveStep(int index, int offset) {
    final destination = index + offset;
    if (destination < 0 || destination >= _steps.length) return;
    setState(() {
      final step = _steps.removeAt(index);
      _steps.insert(destination, step);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * .78,
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text('New routine',
                              style: AppTextStyles.titleMedium),
                        ),
                        TextButton(
                          key: const ValueKey('routine-save-top'),
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving…' : 'Save'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.lg),
                    TextField(
                      controller: _nameController,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        labelText: 'Routine name',
                        hintText: 'Morning launch pad',
                      ),
                    ),
                    const SizedBox(height: AppSpace.md),
                    const Text('CHECKLIST', style: AppTextStyles.label),
                    const SizedBox(height: AppSpace.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _stepController,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addStep(),
                            decoration: const InputDecoration(
                              labelText: 'Add a step',
                              hintText: 'Brush teeth',
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        IconButton.filled(
                          tooltip: 'Add step',
                          onPressed: _addStep,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    OutlinedButton.icon(
                      onPressed: _addWorkPrepStarter,
                      icon: const Icon(Icons.work_outline),
                      label: const Text('Use work-prep starter'),
                    ),
                    if (_steps.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.md),
                      ...List.generate(
                        _steps.length,
                        (index) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Text('${index + 1}',
                              style: AppTextStyles.monoSmall),
                          title: Text(_steps[index]),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Move step up',
                                icon: const Icon(Icons.keyboard_arrow_up),
                                onPressed: index == 0
                                    ? null
                                    : () => _moveStep(index, -1),
                              ),
                              IconButton(
                                tooltip: 'Move step down',
                                icon: const Icon(Icons.keyboard_arrow_down),
                                onPressed: index == _steps.length - 1
                                    ? null
                                    : () => _moveStep(index, 1),
                              ),
                              IconButton(
                                tooltip: 'Remove step',
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    setState(() => _steps.removeAt(index)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.md),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_outlined),
                      title: const Text('Specific time'),
                      subtitle: Text(_time.format(context)),
                      onTap: _pickTime,
                    ),
                    const SizedBox(height: AppSpace.md),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save routine'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  final Routine routine;
  const _RoutineCard({required this.routine});

  String get _timeLabel {
    switch (routine.anchor) {
      case RoutineAnchor.morning:
        return 'Morning';
      case RoutineAnchor.midday:
        return 'Midday';
      case RoutineAnchor.evening:
        return 'Evening';
      case RoutineAnchor.custom:
        final h = routine.scheduleHour ?? 0;
        final m = routine.scheduleMinute ?? 0;
        final mm = m.toString().padLeft(2, '0');
        final period = h >= 12 ? 'PM' : 'AM';
        final h12 = h % 12 == 0 ? 12 : h % 12;
        return '$h12:$mm $period';
    }
  }

  String? get _daysLabel {
    final d = routine.activeDays;
    if (d == null || d.isEmpty || d.length == 7) return null;
    if (d == '12345') return 'Weekdays';
    if (d == '67') return 'Weekends';
    return d.split('').join(',');
  }

  @override
  Widget build(BuildContext context) {
    final done = routine.completedCount;
    final total = routine.steps.length;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpace.radiusCard),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpace.radiusCard),
        onTap: () => launchRoutine(context, routine),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.name, style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      _daysLabel == null
                          ? _timeLabel
                          : '$_timeLabel · $_daysLabel',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              Text('$done/$total', style: AppTextStyles.monoSmall),
              const SizedBox(width: AppSpace.sm),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
