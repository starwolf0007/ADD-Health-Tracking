// lib/presentation/today_screen.dart
//
// Today screen — the single surface users see on open.
// Consumes todayControllerProvider (AsyncNotifier) and renders:
//   • Normal mode  : Next Best Action card + reason line
//   • Quick Wins   : ≤3 low-effort task cards with reassurance line
//   • Empty        : All-clear state
//   • Heartbeat    : Live completed-today count (mono font, state-transition
//                    only — no idle animation per spec v1.3)
//   • FAB          : Capture sheet (§13 — one gesture from anywhere)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/routine.dart';
import '../domain/task.dart';
import '../executive/planner.dart';
import '../providers.dart';
import 'habits_widget.dart';
import 'routine_screen.dart';
import 'settings_screen.dart';
import 'theme.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayAsync = ref.watch(todayControllerProvider);
    final completedAsync = ref.watch(completedTodayCountProvider);
    final nameAsync = ref.watch(displayNameProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: _GreetingHeader(nameAsync: nameAsync),
        actions: [
          // Heartbeat count lives in trailing position — §13 token
          _HeartbeatCount(completedAsync: completedAsync),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: AppColors.textSecondary, size: 20),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const SettingsScreen(),
              ),
            ),
          ),
        ],
      ),
      body: todayAsync.when(
        loading: () => const _LoadingBody(),
        error: (e, _) => _ErrorBody(error: e),
        data: (state) => SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TodayBody(state: state),
              const _DueRoutinesSection(),
              const SizedBox(height: 8),
              const HabitsWidget(),
              const SizedBox(height: 100), // FAB clearance
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCaptureSheet(context, ref),
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCaptureSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _CaptureSheet(ref: ref),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _GreetingHeader extends StatelessWidget {
  final AsyncValue<String> nameAsync;

  const _GreetingHeader({required this.nameAsync});

  @override
  Widget build(BuildContext context) {
    final name = nameAsync.valueOrNull ?? '';
    final greeting = name.isNotEmpty ? 'Hey, $name' : 'Today';
    return Text(
      greeting,
      style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimary),
    );
  }
}

class _HeartbeatCount extends StatelessWidget {
  final AsyncValue<int> completedAsync;

  const _HeartbeatCount({required this.completedAsync});

  @override
  Widget build(BuildContext context) {
    final count = completedAsync.valueOrNull ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline,
            size: 14, color: count > 0 ? AppColors.accent : AppColors.textMuted),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: AppTextStyles.monoSmall.copyWith(
            color: count > 0 ? AppColors.accent : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Body states
// ---------------------------------------------------------------------------

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: AppColors.accent,
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final Object error;

  const _ErrorBody({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Something went wrong. Try restarting the app.',
          style: AppTextStyles.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _TodayBody extends ConsumerWidget {
  final TodayState state;

  const _TodayBody({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (state.mode) {
      DayMode.quickWins => _QuickWinsBody(state: state, ref: ref),
      DayMode.normal => state.primaryTask == null
          ? const _AllClearBody()
          : _NormalBody(state: state, ref: ref),
    };
  }
}

// ---------------------------------------------------------------------------
// Normal mode
// ---------------------------------------------------------------------------

class _NormalBody extends StatelessWidget {
  final TodayState state;
  final WidgetRef ref;

  const _NormalBody({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    final task = state.primaryTask!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Next up', style: AppTextStyles.bodySmall),
          const SizedBox(height: 12),
          _TaskCard(task: task, onComplete: () {
            ref.read(todayControllerProvider.notifier).complete(task.id);
          }),
          if (state.reason.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(state.reason, style: AppTextStyles.bodySmall),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick Wins mode
// ---------------------------------------------------------------------------

class _QuickWinsBody extends StatelessWidget {
  final TodayState state;
  final WidgetRef ref;

  const _QuickWinsBody({required this.state, required this.ref});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.reason,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.accent),
          ),
          const SizedBox(height: 16),
          ...state.quickWins.map(
            (task) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TaskCard(
                task: task,
                onComplete: () {
                  ref.read(todayControllerProvider.notifier).complete(task.id);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// All clear
// ---------------------------------------------------------------------------

class _AllClearBody extends StatelessWidget {
  const _AllClearBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline,
              size: 48, color: AppColors.accent.withOpacity(0.6)),
          const SizedBox(height: 16),
          Text('All clear', style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text('Nothing pending — add something with +',
              style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task card
// ---------------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onComplete;

  const _TaskCard({required this.task, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _EnergyGlyph(energy: task.energy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: AppTextStyles.bodyMedium),
                if (task.notes != null && task.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(task.notes!, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onComplete,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.textMuted, width: 1.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.check,
                  size: 16, color: AppColors.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

// Energy glyph — monochrome, shape-distinguished (no colour coding per §13)
class _EnergyGlyph extends StatelessWidget {
  final EnergyLevel energy;

  const _EnergyGlyph({required this.energy});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (energy) {
      EnergyLevel.low => (Icons.remove, 'low'),
      EnergyLevel.medium => (Icons.circle_outlined, 'medium'),
      EnergyLevel.high => (Icons.keyboard_arrow_up, 'high'),
    };
    return Semantics(
      label: '$label energy',
      child:
          Icon(icon, size: 18, color: AppColors.textSecondary),
    );
  }
}

// ---------------------------------------------------------------------------
// Capture sheet
// ---------------------------------------------------------------------------

class _CaptureSheet extends StatefulWidget {
  final WidgetRef ref;

  const _CaptureSheet({required this.ref});

  @override
  State<_CaptureSheet> createState() => _CaptureSheetState();
}

class _CaptureSheetState extends State<_CaptureSheet> {
  final _controller = TextEditingController();
  EnergyLevel _energy = EnergyLevel.medium;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add task', style: AppTextStyles.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: 'What needs doing?',
              hintStyle: AppTextStyles.bodySmall,
              filled: true,
              fillColor: AppColors.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Energy to start', style: AppTextStyles.bodySmall),
          const SizedBox(height: 8),
          Row(
            children: EnergyLevel.values.map((e) {
              final selected = e == _energy;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(e.name),
                  selected: selected,
                  onSelected: (_) => setState(() => _energy = e),
                  selectedColor: AppColors.accent,
                  backgroundColor: AppColors.surfaceVariant,
                  labelStyle: AppTextStyles.bodySmall.copyWith(
                    color: selected
                        ? AppColors.background
                        : AppColors.textSecondary,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Add'),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() async {
    final title = _controller.text.trim();
    if (title.isEmpty) return;

    final task = Task.create(title: title, energy: _energy);
    try {
      await widget.ref.read(todayControllerProvider.notifier).addTask(task);
      Navigator.of(context).pop();
    } catch (e) {
      // Show error to user if task creation fails
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Due routines section — shown between tasks and habits
// ---------------------------------------------------------------------------

/// Shows routines that are due right now (time-of-day aware).
/// Hidden when no routines are due — zero visual noise.
class _DueRoutinesSection extends ConsumerWidget {
  const _DueRoutinesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueAsync = ref.watch(dueRoutinesProvider);

    return dueAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (routines) {
        if (routines.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text('Routines', style: AppTextStyles.bodySmall),
            ),
            ...routines.map(
              (r) => _RoutineCard(
                routine: r,
                onTap: () => launchRoutine(context, ref, r),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Single tappable routine card.
/// Shows progress state when a routine is already in progress.
class _RoutineCard extends StatelessWidget {
  final Routine routine;
  final VoidCallback onTap;

  const _RoutineCard({required this.routine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inProgress = routine.completedCount > 0 && !routine.isComplete;
    final totalMinutes = routine.steps.fold<int>(
      0,
      (sum, s) => sum + (s.durationMinutes ?? 0),
    );
    final stepLabel = inProgress
        ? '${routine.completedCount} / ${routine.steps.length} steps'
        : '${routine.steps.length} steps · ~$totalMinutes min';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            // Accent border when already in progress — signals continuation
            border: inProgress
                ? Border.all(
                    color: AppColors.accent.withValues(alpha: 0.35),
                    width: 1,
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(routine.name, style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 2),
                    Text(stepLabel, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Text(
                inProgress ? 'Continue' : 'Start',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.accent),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
