// lib/presentation/routine_screen.dart
//
// Routine execution screen — surfaces ONE step at a time.
//
// ADHD UX principles applied:
//   • Only the current step is prominent. Others exist but are de-emphasized.
//   • Progress bar is subtle — enough to feel movement, not overwhelming.
//   • Completing the last step triggers a brief celebration then returns to Today.
//   • "Skip step" is available without judgement — sometimes a step just won't happen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/domain/routine.dart';
import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/presentation/theme.dart';

// ---------------------------------------------------------------------------
// The screen receives the full Routine and calls back when done/exited.
// Phase 2 will wire this through a proper RoutineController + provider;
// for now it's self-contained stateful to keep the PR small.
// ---------------------------------------------------------------------------

class RoutineScreen extends ConsumerStatefulWidget {
  final Routine routine;
  final VoidCallback onFinished;

  const RoutineScreen({
    super.key,
    required this.routine,
    required this.onFinished,
  });

  @override
  ConsumerState<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends ConsumerState<RoutineScreen>
    with SingleTickerProviderStateMixin {
  late List<RoutineStep> _steps;
  bool _showCelebration = false;
  late AnimationController _progressController;
  late Animation<double> _progressAnim;

  @override
  void initState() {
    super.initState();
    _steps = List<RoutineStep>.from(widget.routine.steps);
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _progressAnim = Tween<double>(begin: 0, end: _completedFraction).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.easeOut));
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  double get _completedFraction {
    if (_steps.isEmpty) return 0;
    return _steps.where((s) => s.isComplete).length / _steps.length;
  }

  RoutineStep? get _activeStep {
    final pending = _steps.where((s) => !s.isComplete).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    return pending.isEmpty ? null : pending.first;
  }

  void _completeStep(String stepId) {
    RoutineStep? updated;
    setState(() {
      final idx = _steps.indexWhere((s) => s.id == stepId);
      if (idx != -1) {
        updated = _steps[idx].copyWith(isComplete: true);
        _steps[idx] = updated!;
      }
    });
    _animateProgress();

    // Persist to DB — fire-and-forget, UI already updated optimistically.
    if (updated != null) {
      ref.read(routineRepositoryProvider).updateStep(updated!);
    }

    if (_completedFraction >= 1.0) {
      _onAllDone();
    }
  }

  void _skipStep(String stepId) {
    // Skip = mark complete without ceremony. No judgement.
    _completeStep(stepId);
  }

  void _animateProgress() {
    final target = _completedFraction;
    _progressAnim = Tween<double>(
      begin: _progressAnim.value,
      end: target,
    ).animate(
        CurvedAnimation(parent: _progressController, curve: Curves.easeOut));
    _progressController
      ..reset()
      ..forward();
  }

  void _onAllDone() {
    setState(() => _showCelebration = true);
    Future.delayed(const Duration(seconds: 2), widget.onFinished);
  }

  @override
  Widget build(BuildContext context) {
    if (_showCelebration) {
      return _CelebrationView(routineName: widget.routine.name);
    }

    final active = _activeStep;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: widget.onFinished,
          tooltip: 'Exit routine',
        ),
        title: Text(
          widget.routine.name,
          style: AppTextStyles.titleMedium,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 16),
            child: Text(
              '${_steps.where((s) => s.isComplete).length}/${_steps.length}',
              style: AppTextStyles.monoSmall,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Subtle progress bar — updates on step completion (no idle animation)
          AnimatedBuilder(
            animation: _progressAnim,
            builder: (_, __) => _ProgressBar(fraction: _progressAnim.value),
          ),
          Expanded(
            child: active == null
                ? const Center(
                    child: Text('All done!', style: AppTextStyles.titleMedium))
                : _StepView(
                    step: active,
                    stepNumber: _steps.where((s) => s.isComplete).length + 1,
                    total: _steps.length,
                    onComplete: () => _completeStep(active.id),
                    onSkip: () => _skipStep(active.id),
                  ),
          ),
          // Upcoming steps — de-emphasized list
          if (_steps.where((s) => !s.isComplete).length > 1)
            _UpNextList(
              steps: _steps.where((s) => !s.isComplete).toList()
                ..sort((a, b) => a.position.compareTo(b.position))
                ..removeAt(0), // active step is shown above
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Progress bar
// ---------------------------------------------------------------------------

class _ProgressBar extends StatelessWidget {
  final double fraction;

  const _ProgressBar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 2,
      color: AppColors.surfaceVariant,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(color: AppColors.accent),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active step card
// ---------------------------------------------------------------------------

class _StepView extends StatelessWidget {
  final RoutineStep step;
  final int stepNumber;
  final int total;
  final VoidCallback onComplete;
  final VoidCallback onSkip;

  const _StepView({
    required this.step,
    required this.stepNumber,
    required this.total,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step $stepNumber of $total',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 20),
          Text(
            step.title,
            style: AppTextStyles.displayLarge,
          ),
          if (step.notes != null && step.notes!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(step.notes!,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary)),
          ],
          if (step.durationMinutes != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(
                  '${step.durationMinutes} min',
                  style: AppTextStyles.monoSmall,
                ),
              ],
            ),
          ],
          const Spacer(),
          // Done button — primary CTA
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onComplete,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.background,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done', style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 10),
          // Skip — no judgement, same visual weight as a secondary link
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip this step',
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Up-next list
// ---------------------------------------------------------------------------

class _UpNextList extends StatelessWidget {
  final List<RoutineStep> steps;

  const _UpNextList({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.surfaceVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Up next', style: AppTextStyles.bodySmall),
          const SizedBox(height: 8),
          ...steps.take(3).map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '· ${s.title}',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )),
          if (steps.length > 3)
            Text(
              '+ ${steps.length - 3} more',
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Celebration (shown for 2s after last step done)
// ---------------------------------------------------------------------------

class _CelebrationView extends StatelessWidget {
  final String routineName;

  const _CelebrationView({required this.routineName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 64, color: AppColors.accent),
              const SizedBox(height: 24),
              Text(routineName, style: AppTextStyles.titleMedium),
              const SizedBox(height: 8),
              Text('Routine complete',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: AppColors.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry point helper — push RoutineScreen as a full-screen route
// ---------------------------------------------------------------------------

Future<void> launchRoutine(BuildContext context, Routine routine) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => RoutineScreen(
        routine: routine,
        onFinished: () => Navigator.of(context).pop(),
      ),
    ),
  );
}
