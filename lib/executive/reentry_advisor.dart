// lib/executive/reentry_advisor.dart
//
// Re-entry advisory logic for paused tasks.
// Phase 2 STAGE 3: Analyzes paused tasks and suggests next actions.
//
// Phase 2 uses heuristics (parsing task title/notes) to estimate progress.
// Phase 3 will track actual step completion in the database.

import '../domain/task.dart';

class ReentryData {
  /// Progress percentage (0-100) — estimated from notes/title parsing.
  final int progressPercent;

  /// Where they paused — extracted from last line of notes or title.
  /// Example: "Step 4: Deploy" or null if unable to infer.
  final String? pausedAtStep;

  /// One small suggested action to resume (1-3 words max).
  /// Example: "Check logs", "Merge PR", "Send reply".
  final String suggestedAction;

  const ReentryData({
    required this.progressPercent,
    this.pausedAtStep,
    required this.suggestedAction,
  });
}

class ReentryAdvisor {
  /// Analyze a paused task and compute re-entry data.
  ///
  /// Phase 2 heuristics:
  ///   - Progress: count newline-delimited "steps" in task.notes
  ///   - Paused at: take last line of task.notes
  ///   - Action: infer from task title (e.g., "Deploy X" → "Check logs")
  ///
  /// Phase 3: will use real step/subtask completion tracking from database.
  ReentryData analyzeTask(Task pausedTask) {
    if (pausedTask.status != TaskStatus.paused) {
      // Fallback for non-paused tasks (shouldn't happen in normal flow).
      return ReentryData(
        progressPercent: 0,
        pausedAtStep: null,
        suggestedAction: 'Continue',
      );
    }

    // Extract steps from notes.
    final steps = _extractSteps(pausedTask.notes ?? '');
    final progress = _estimateProgress(steps.length);
    final pausedAt = _extractPausedAtStep(pausedTask.notes ?? '', steps);
    final action = _suggestAction(pausedTask.title);

    return ReentryData(
      progressPercent: progress,
      pausedAtStep: pausedAt,
      suggestedAction: action,
    );
  }

  /// Parse task notes into discrete steps.
  ///
  /// Recognizes:
  ///   - Numbered steps: "1. Step", "2) Step", etc.
  ///   - Bullet points: "- Step", "* Step", "• Step"
  ///   - Blank lines separate steps
  ///
  /// Returns a list of step strings (non-empty lines).
  List<String> _extractSteps(String notes) {
    if (notes.trim().isEmpty) return [];

    final lines = notes.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return lines;
  }

  /// Estimate progress percentage based on step count.
  ///
  /// Heuristic: if we see 5 lines, assume 5 steps total.
  /// Then progress = (steps.length) / (steps.length + 2) * 100
  /// This gives a modest boost for visible progress without claiming 100% until complete.
  ///
  /// Examples:
  ///   - 1 line → ~33%
  ///   - 3 lines → ~60%
  ///   - 5 lines → ~71%
  ///
  /// Phase 3: replace with actual (completed / total) * 100.
  int _estimateProgress(int stepCount) {
    if (stepCount == 0) return 0;
    if (stepCount == 1) return 25;
    if (stepCount <= 3) return 50;
    if (stepCount <= 5) return 60;
    // For longer notes, cap at 75% — not complete until marked complete.
    return 75;
  }

  /// Extract "paused at" step — the last line of notes.
  String? _extractPausedAtStep(String notes, List<String> steps) {
    if (steps.isEmpty) return null;

    // Take the last line as the "current" step.
    final lastStep = steps.last;

    // Clean up common prefixes (numbers, bullets).
    final cleaned = lastStep
        .replaceAll(RegExp(r'^[0-9]+[\.\)]\s*'), '') // numbered: "1. " or "1) "
        .replaceAll(RegExp(r'^[-*•]\s*'), '') // bullet: "- " or "* " or "• "
        .trim();

    return cleaned.isNotEmpty ? cleaned : null;
  }

  /// Suggest a next action based on task title.
  ///
  /// Heuristic pattern matching on verbs in the title.
  /// Examples:
  ///   - "Deploy X" → "Check logs"
  ///   - "Review PR" → "Merge if approved"
  ///   - "Write email" → "Send it"
  ///   - "Setup database" → "Test connection"
  ///
  /// Default: "Continue" if no pattern matched.
  String _suggestAction(String title) {
    final lower = title.toLowerCase();

    // Pattern → suggested action
    const patterns = {
      'deploy': 'Check logs',
      'review': 'Merge if approved',
      'write': 'Send it',
      'email': 'Send reply',
      'setup': 'Test it',
      'configure': 'Test it',
      'install': 'Verify install',
      'build': 'Run tests',
      'debug': 'Test again',
      'test': 'Run tests',
      'fix': 'Test fix',
      'merge': 'Merge it',
      'push': 'Create PR',
      'commit': 'Push to main',
      'prepare': 'Start working',
      'plan': 'Start working',
      'think': 'Plan it out',
      'research': 'Document findings',
      'document': 'Share docs',
      'refactor': 'Run tests',
      'optimize': 'Measure results',
    };

    for (final entry in patterns.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }

    // Default fallback.
    return 'Continue';
  }
}
