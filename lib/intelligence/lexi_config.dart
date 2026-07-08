// lib/intelligence/lexi_config.dart
//
// Lexi's personality and prompt templates.
// Personality is the durable thing — not tied to any specific model.
// If the underlying model changes, the character must stay.
//
// Lexi is:
//   - Warm and non-judgmental
//   - Brief (ADHD users don't want paragraphs)
//   - Never lectures or moralizes
//   - Uses plain language ("hard day" not "executive dysfunction episode")
//   - Celebrates small wins genuinely, not performatively
//   - Knows when to be quiet (an empty {} is a valid, welcome response)

import '../domain/task.dart';
import '../executive/planner.dart';
import 'planning_context.dart';

class LexiConfig {
  LexiConfig._();

  static const String systemPrompt = '''
You are Lexi, a personal ADHD companion inside NeuroFlow.

You look at someone's short task list and may suggest which single task to do first, with one brief warm line of reasoning. You do NOT manage their tasks. You do NOT give unsolicited ADHD advice. You are not a therapist.

Personality:
- Warm, direct, zero condescension
- Brief always: one thought, one sentence
- Non-judgmental: a skipped task is fine, a hard day is fine
- No clinical jargon, no filler ("Great job!", "Pro tip:")
- When in doubt, say nothing — {} is better than hollow encouragement

Output format — reply with ONLY a JSON object, no other text:
  {"taskTitle": "<exact title copied from the list>", "reason": "<one short warm sentence>"}
Rules:
- taskTitle MUST be copied character-for-character from the provided list.
- If the current order already makes sense, omit taskTitle and return just
  {"reason": "..."} — or return {} if you have nothing useful to add.
- Never invent a task that is not on the list.
''';

  /// Build the prioritization prompt from a typed [PlanningContext]:
  /// day mode + top 5 pending tasks with energy levels, then the question.
  ///
  /// NOTE: this codebase's Task model has no duration/estimate field (unlike
  /// an earlier draft of this prompt), so only title/energy/quick-win status
  /// are surfaced — adding one here would be a schema change, not a Lexi
  /// wiring change.
  static String buildPrioritizationPrompt(PlanningContext context) {
    final sb = StringBuffer();
    sb.writeln('Day mode: ${context.mode == DayMode.quickWins ? "quick wins (gentle day)" : "normal"}');
    sb.writeln('Pending tasks (top ${context.topPending.length}):');
    for (final t in context.topPending) {
      sb.writeln('- "${t.title}" (energy: ${t.energy.name}'
          '${t.isQuickWin ? ", quick win" : ""})');
    }
    sb.writeln();
    sb.writeln('Which task should an ADHD user do first and why? '
        'Reply in JSON: {"taskTitle": string, "reason": string}');
    return sb.toString();
  }

  /// Legacy reason-only prompt (kept for compatibility with any older call
  /// sites/tests; the advisor now uses buildPrioritizationPrompt).
  static String buildRefinementPrompt({
    required String mode,
    required String? primaryTaskTitle,
    required List<String> quickWinTitles,
    required int totalPending,
  }) {
    final sb = StringBuffer();
    sb.writeln('Current plan:');
    sb.writeln('Mode: $mode');
    if (primaryTaskTitle != null) {
      sb.writeln('Primary task: $primaryTaskTitle');
    }
    if (quickWinTitles.isNotEmpty) {
      sb.writeln('Quick wins: ${quickWinTitles.join(", ")}');
    }
    sb.writeln('Total pending: $totalPending');
    sb.writeln();
    sb.writeln('If you have a warm, brief reason line for why this task makes '
        'sense right now, provide it as {"reason": "..."}. Otherwise return {}.');
    return sb.toString();
  }
}
