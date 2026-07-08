// lib/intelligence/lexi_plan_advisor.dart
//
// LexiPlanAdvisor — on-device AI refinement via Gemini Nano (Android AICore).
//
// Architecture (§14 + DEC-003):
//   • On-device by default. Cloud Gemini requires explicit user opt-in.
//   • NEVER throws — always returns the plan unchanged on any error.
//   • Falls back to NoOp behaviour silently when Gemini Nano is unavailable
//     (unsupported device, model not downloaded, API < 34, emulator, …).
//   • Lexi may REORDER within the deterministic candidate set (primaryTask /
//     quickWins) and REWORD the reason line. She may not invent a task that
//     isn't already in [allPending], or change plan.mode — task *selection*
//     stays fully deterministic; only *order* and *reason* are AI-influenced.
//     AI refines; it never authors. (DEC-003)
//
// Fallback chain (airtight, by construction):
//   unavailable → plan unchanged
//   channel error / PlatformException → plan unchanged
//   >5s timeout (Dart-side, independent of the Kotlin 5s cap) → plan unchanged
//   malformed / non-JSON / empty response → plan unchanged
//   suggested taskTitle doesn't match a real pending task → plan unchanged
//   The user can never see a crash, a stalled spinner, or an empty reason
//   from a Lexi failure — the deterministic plan is always already complete.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/task.dart';
import '../executive/planner.dart';
import 'lexi_config.dart';
import 'planning_context.dart';

class LexiPlanAdvisor implements PlanAdvisor {
  static const _channel = MethodChannel('neuroflow/lexi');
  static const _dartTimeout = Duration(seconds: 5);

  /// Cached per advisor instance. The provider recreates the advisor when the
  /// tier changes, so a device that gains the model mid-session picks it up
  /// on the next provider rebuild (or app restart) — acceptable for a
  /// feature that is pure enrichment.
  bool? _isAvailable;

  @override
  Future<Plan> refine(Plan plan, List<Task> allPending) async {
    try {
      final available = await _checkAvailability();
      if (!available) return plan;

      // Nothing to prioritize → nothing to ask.
      if (allPending.isEmpty) return plan;

      final context = PlanningContext.fromPlan(plan, allPending);
      final prompt = LexiConfig.buildPrioritizationPrompt(context);

      final response = await _generate(
        systemPrompt: LexiConfig.systemPrompt,
        userMessage: prompt,
      );
      if (response == null || response.trim().isEmpty) return plan;

      return _applyResponse(plan, allPending, response);
    } catch (_) {
      // Silent fallback — never surface LLM errors to the user.
      return plan;
    }
  }

  // ---------------------------------------------------------------------
  // Response application — the only place Lexi's output touches the plan
  // ---------------------------------------------------------------------

  Plan _applyResponse(Plan plan, List<Task> allPending, String raw) {
    final json = _parseJsonObject(raw);
    if (json == null) return plan;

    final suggestedTitle = (json['taskTitle'] as String?)?.trim();
    final reason = (json['reason'] as String?)?.trim();

    // {} — Lexi chose silence. A valid, welcome answer.
    if ((suggestedTitle == null || suggestedTitle.isEmpty) &&
        (reason == null || reason.isEmpty)) {
      return plan;
    }

    // Reason-only refinement: reword the line, change nothing structural.
    if (suggestedTitle == null || suggestedTitle.isEmpty) {
      if (reason == null || reason.isEmpty) return plan;
      return plan.copyWith(reason: reason);
    }

    // Title suggested → it must resolve to a REAL task in the deterministic
    // candidate set, or the whole response is treated as a parse failure.
    final match = _resolveTask(suggestedTitle, allPending);
    if (match == null) return plan;

    switch (plan.mode) {
      case DayMode.normal:
        return plan.copyWith(
          primaryTask: match,
          reason: (reason == null || reason.isEmpty) ? plan.reason : reason,
        );
      case DayMode.quickWins:
        // Reorder within the existing quick-wins list only. If the match
        // isn't in that list, leave the gentle plan exactly as it is —
        // quickWins mode exists to protect a rough day from churn.
        final idx = plan.quickWins.indexWhere((t) => t.id == match.id);
        if (idx < 0) return plan;
        final reordered = List<Task>.from(plan.quickWins)
          ..removeAt(idx)
          ..insert(0, match);
        return plan.copyWith(
          quickWins: reordered,
          reason: (reason == null || reason.isEmpty) ? plan.reason : reason,
        );
    }
  }

  /// Exact-match first, then trimmed case-insensitive. Anything fuzzier than
  /// that risks Lexi "matching" the wrong task — worse than not reordering.
  Task? _resolveTask(String title, List<Task> pending) {
    for (final t in pending) {
      if (t.title == title) return t;
    }
    final needle = title.toLowerCase();
    for (final t in pending) {
      if (t.title.trim().toLowerCase() == needle) return t;
    }
    return null;
  }

  /// Tolerates ```json fences and stray prose around the object — small
  /// models decorate. Extracts the first {...} block; null if none parses.
  Map<String, dynamic>? _parseJsonObject(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceAll(RegExp(r'^```(json)?', multiLine: true), '');
      s = s.replaceAll('```', '').trim();
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(s.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // Channel plumbing
  // ---------------------------------------------------------------------

  Future<bool> _checkAvailability() async {
    _isAvailable ??= await _checkAvailabilityNative();
    return _isAvailable!;
  }

  Future<bool> _checkAvailabilityNative() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('checkGeminiNanoAvailable')
          .timeout(_dartTimeout);
      return result ?? false;
    } on MissingPluginException {
      return false; // channel not registered (e.g. iOS, tests)
    } catch (_) {
      return false; // PlatformException, TimeoutException, anything
    }
  }

  Future<String?> _generate({
    required String systemPrompt,
    required String userMessage,
  }) async {
    try {
      // Dart-side 5s ceiling, independent of the Kotlin-side cap — covers
      // channel latency and any native path that forgets to time out.
      final result = await _channel.invokeMethod<String>('generateResponse', {
        'systemPrompt': systemPrompt,
        'userMessage': userMessage,
        'maxTokens': 120, // short JSON: {taskTitle, reason}
        'temperature': 0.7,
      }).timeout(_dartTimeout);
      return result;
    } on MissingPluginException {
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null; // includes PlatformException("LEXI_TIMEOUT")
    }
  }
}

// ---------------------------------------------------------------------------
// CloudPlanAdvisor — Phase 3, explicit user opt-in only (§14)
// Never activated by default. Provider swap happens in settings.
// ---------------------------------------------------------------------------

class CloudGeminiPlanAdvisor implements PlanAdvisor {
  /// The user's Gemini API key — stored in FlutterSecureStorage (§2.8).
  /// Never hardcoded. If null, falls back silently.
  final String? apiKey;

  const CloudGeminiPlanAdvisor({this.apiKey});

  @override
  Future<Plan> refine(Plan plan, List<Task> allPending) async {
    // Phase 3 scope: cloud Gemini via googleapis, gated on explicit consent.
    // Until that phase, identical to NoOp: the plan passes through unchanged.
    return plan;
  }
}
