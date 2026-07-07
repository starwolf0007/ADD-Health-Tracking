// lib/executive/lexi_plan_advisor.dart
//
// LexiPlanAdvisor — on-device AI refinement via Gemini Nano (Android).
//
// Architecture (§14):
//   • On-device by default. Cloud Gemini requires explicit user opt-in.
//   • NEVER throws — always returns plan unchanged on any error.
//   • Falls back to NoOpPlanAdvisor behaviour silently if Gemini Nano
//     is unavailable (device doesn't support it, SDK not yet stable, etc.)
//
// Fallback contract (airtight): on ANY failure — device/SDK unavailable, the
// 5-second timeout enforced in LexiBridge.generate, a malformed/non-JSON
// response, or any other exception — refine() returns [plan] completely
// unchanged. The user must never see a crash, a stalled spinner, or an
// empty/blank reason line caused by a Lexi failure; TodayController always
// has a fully usable, deterministic plan to fall back on.
//
// Reordering contract: Lexi may re-rank tasks the Executive already chose as
// candidates (the quick-wins list), but may never introduce a task the
// Executive didn't select — task *membership* in the plan stays fully
// deterministic (§14: "deterministic Executive never depends on AI"); only
// *order* among Executive-approved candidates and the *reason* line are
// AI-influenced.
//
// See: https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/task.dart';
import '../intelligence/lexi_bridge.dart';
import 'lexi_config.dart';
import 'planner.dart';

class LexiPlanAdvisor implements PlanAdvisor {
  /// Whether Gemini Nano is available on this device. Cached after the
  /// first check for the lifetime of this advisor instance.
  bool? _isAvailable;

  @override
  Future<Plan> refine(Plan plan, List<Task> allPending) async {
    try {
      final available = await _checkAvailability();
      if (!available) return plan;

      final prompt = LexiConfig.buildRefinementPrompt(
        mode: plan.mode.name,
        primaryTaskTitle: plan.primaryTask?.title,
        quickWinTitles: plan.quickWins.map((t) => t.title).toList(),
        totalPending: allPending.length,
      );

      // The 5-second timeout is enforced inside LexiBridge.generate — it
      // returns null on timeout exactly like any other failure, so the
      // single null-check below is the entire timeout-handling path.
      final response = await LexiBridge.generate(
        systemPrompt: LexiConfig.systemPrompt,
        userMessage: prompt,
        maxTokens: 80,
      );

      if (response == null || response.isEmpty) return plan;

      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic>) return plan;

      final reason = _cleanString(decoded['reason']);
      final taskTitle = _cleanString(decoded['taskTitle']);

      final reordered =
          taskTitle == null ? plan : _reorderByTitle(plan, taskTitle);

      if (reason == null && identical(reordered, plan)) {
        // Neither field produced a usable change.
        return plan;
      }

      return Plan(
        mode: reordered.mode,
        primaryTask: reordered.primaryTask,
        quickWins: reordered.quickWins,
        reason: reason ?? reordered.reason,
      );
    } catch (e) {
      // Airtight fallback: JSON parse errors, type-cast failures, or
      // anything else lands here and returns the plan unchanged. Logged
      // silently — category only, never the prompt/response content.
      if (kDebugMode) {
        debugPrint('LexiPlanAdvisor.refine() failed: ${e.runtimeType}');
      }
      return plan;
    }
  }

  Future<bool> _checkAvailability() async {
    _isAvailable ??= await LexiBridge.isAvailable();
    return _isAvailable!;
  }

  /// Returns [value] trimmed, or null unless it's a non-empty string.
  String? _cleanString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Re-ranks the plan's OWN candidate tasks so [taskTitle] leads, without
  /// ever pulling in a task the Executive didn't already select.
  ///
  ///  - quickWins mode: if [taskTitle] matches one of `plan.quickWins`
  ///    (case-insensitive, trimmed), move it to the front; relative order of
  ///    the rest is preserved. No match (including a hallucinated title) or
  ///    an already-first match returns [plan] unchanged.
  ///  - normal mode: there is exactly one Executive-selected candidate
  ///    (`primaryTask`). Lexi cannot promote a different task into that slot
  ///    — that would make task *selection*, not just order, AI-dependent —
  ///    so [taskTitle] is never actionable here and [plan] is returned as-is.
  Plan _reorderByTitle(Plan plan, String taskTitle) {
    if (plan.mode != DayMode.quickWins) return plan;

    final normalized = taskTitle.toLowerCase();
    final index = plan.quickWins.indexWhere(
      (t) => t.title.trim().toLowerCase() == normalized,
    );
    if (index <= 0) return plan; // no match, or already first

    final reordered = List<Task>.from(plan.quickWins);
    final promoted = reordered.removeAt(index);
    reordered.insert(0, promoted);

    return Plan(
      mode: plan.mode,
      primaryTask: plan.primaryTask,
      quickWins: reordered,
      reason: plan.reason,
    );
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
    // TODO(phase3): implement cloud Gemini call via googleapis package.
    // Requires: valid apiKey, network, explicit user consent in settings.
    // Until implemented, return plan unchanged.
    return plan;
  }
}
