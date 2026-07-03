// lib/presentation/routine_screen.dart
//
// Routine execution — ONE step at a time.
// (The original design here was right; this pass completes the file — it was
// truncated mid-`launchRoutine` — and moves magic numbers onto theme tokens.)
//
// ADHD UX principles:
//   • Only the current step is prominent; the rest are de-emphasized.
//   • Progress bar is subtle — movement without pressure.
//   • Finishing the last step shows a brief celebration, then returns.
//   • "Skip" is always available, no judgement, no confirmation friction.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/routine.dart';
import 'theme.dart';

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
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );
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

    // Persist — fire-and-forget, UI already updated optimistically.
    if (updated != null) {
      ref.read(routineRepositoryProvider).updateStep(updated!);
    }

    if (_completedFraction >= 1.0) _onAllDone();
  }

  // Skip = complete without ceremony. No judgement.
  void _skipStep(String stepId) => _completeStep(stepId);

  void _animateProgress() {
    _progressAnim = Tween<double>(
      begin: _progressAnim.value,
      end: _completedFraction,
    ).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeOut),
    );
    _progressController
      ..reset()
      ..forward();
  }

  void _onAllDone() {
    setState(() => _showCelebration = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) widget.onFinished();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showCelebration) {
      return _CelebrationView(routineName: widget.routine.name);
    }

    final active = _activeStep;
    final doneCount = _steps.where((s) => s.isComplete).length;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textSecondary),
          onPressed: widget.onFinished,
          tooltip: 'Exit routine',
        ),
        title: Text(widget.routine.name, style: AppTextStyles.titleMedium),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: AppSpace.lg),
              child: Text('$doneCount/${_steps.length}',
                  style: AppTextStyles.monoSmall),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Subtle progress — moves only on step completion, no idle motion.
          AnimatedBuilder(
            animation: _progressAnim,
            builder: (_, __) => _ProgressBar(fraction: _progressAnim.value),
          ),
          Expanded(
            child: active == null
                ? const Center(
                    child:
                        Text('All done!', style: AppTextStyles.titleMedium))
                : _StepView(
                    step: active,
                    stepNumber: doneCount + 1,
                    total: _steps.length,
                    onComplete: () => _completeStep(active.id),
                    onSkip: () => _skipStep(active.id),
                  ),
          ),
          if (_steps.where((s) => !s.isComplete).length > 1)
            _UpNextList(
              steps: _steps.where((s) => !s.isComplete).toList()
                ..sort((a, b) => a.position.compareTo(b.position))
                ..removeAt(0),
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
      height: 3,
      color: AppColors.divider,
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction.clamp(0.0, 1.0),
        child: Container(color: AppColors.accent),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active step
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
      padding: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.xxl, AppSpace.xl, AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STEP $stepNumber OF $total', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.xl),
          Text(step.title, style: AppTextStyles.displayLarge),
          if (step.notes != null && step.notes!.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              step.notes!,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
          if (step.durationMinutes != null) ...[
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: AppSpace.xs),
                Text('~${step.durationMinutes} min',
                    style: AppTextStyles.monoSmall),
              ],
            ),
          ],
          const Spacer(),
          ElevatedButton(onPressed: onComplete, child: const Text('Done')),
          const SizedBox(height: AppSpace.sm),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: Text(
                'Skip this step',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Up next — de-emphasized
// ---------------------------------------------------------------------------

class _UpNextList extends StatelessWidget {
  final List<RoutineStep> steps;

  const _UpNextList({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(
          AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('UP NEXT', style: AppTextStyles.label),
          const SizedBox(height: AppSpace.sm),
          ...steps.take(3).map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '·  ${s.title}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          if (steps.length > 3)
            Text('+ ${steps.length - 3} more',
                style:
                    AppTextStyles.bodySmall.copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Celebration — brief, calm
// ---------------------------------------------------------------------------

class _CelebrationView extends StatelessWidget {
  final String routineName;

  const _CelebrationView({required this.routineName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 64, color: AppColors.accent),
              const SizedBox(height: AppSpace.xl),
              Text(routineName, style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpace.sm),
              Text('Routine complete',
                  style:
                      AppTextStyles.bodySmall.copyWith(color: AppColors.accent)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry point — push RoutineScreen as a full-screen route.
// (This helper was the truncation point in the previous version.)
// ---------------------------------------------------------------------------

Future<void> launchRoutine(
  BuildContext context,
  Routine routine, {
  VoidCallback? onFinished,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (routeContext) => RoutineScreen(
        routine: routine,
        onFinished: () {
          Navigator.of(routeContext).pop();
          onFinished?.call();
        },
      ),
    ),
  );
}
