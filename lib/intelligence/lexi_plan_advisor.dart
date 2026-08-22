// lib/executive/lexi_plan_advisor.dart
//
// LexiPlanAdvisor — on-device AI refinement via Gemini Nano (Android).
//
// Architecture (§14):
//   • On-device by default. Cloud Gemini requires explicit user opt-in.
//   • NEVER throws — always returns plan unchanged on any error.
//   • Falls back to NoOpPlanAdvisor behaviour silently if Gemini Nano
//     is unavailable (device doesn't support it, model not downloaded,
//     unsupported hardware, etc.)
//
// Status: Implemented. LexiBridge.kt (android/app/.../lexi/) wires a real
//   com.google.ai.edge.aicore GenerativeModel session — this is not a NoOp.
//   Not independently Verified on-device in this environment: Gemini Nano/
//   AICore requires specific Pixel hardware with the feature available, which
//   this Windows dev environment cannot provide. `flutter analyze`/`flutter
//   test` and a native Gradle compile+unit-test pass are the verification
//   that exists; on-device inference behavior itself needs a real device run.
//
// See: https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android

import 'dart:convert';

import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/intelligence/lexi_bridge.dart';
import 'package:neuroflow/intelligence/lexi_config.dart';
import 'package:neuroflow/executive/planner.dart';

class LexiPlanAdvisor implements PlanAdvisor {
  /// Whether Gemini Nano is available on this device.
  /// Cached after first check.
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

      final response = await _callOnDeviceLLM(
        systemPrompt: LexiConfig.systemPrompt,
        userMessage: prompt,
      );

      if (response == null || response.isEmpty) return plan;

      final json = jsonDecode(response) as Map<String, dynamic>?;
      final reason = json?['reason'] as String?;

      if (reason == null || reason.trim().isEmpty) return plan;

      // Only override the reason line — everything else stays deterministic.
      return Plan(
        mode: plan.mode,
        primaryTask: plan.primaryTask,
        quickWins: plan.quickWins,
        reason: reason.trim(),
      );
    } catch (_) {
      // Silent fallback — never surface LLM errors to the user.
      return plan;
    }
  }

  Future<bool> _checkAvailability() async {
    _isAvailable ??= await _checkAvailabilityNative();
    return _isAvailable!;
  }

  Future<bool> _checkAvailabilityNative() async {
    try {
      return LexiBridge.isAvailable();
    } catch (_) {
      return false;
    }
  }

  Future<String?> _callOnDeviceLLM({
    required String systemPrompt,
    required String userMessage,
  }) async {
    try {
      return LexiBridge.generateResponse(
        systemPrompt: systemPrompt,
        userMessage: userMessage,
        maxTokens: 80,
        temperature: 0.7,
      );
    } catch (_) {
      return null;
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
    // TODO(phase3): implement cloud Gemini call via googleapis package.
    // Requires: valid apiKey, network, explicit user consent in settings.
    // Until implemented, return plan unchanged.
    return plan;
  }
}
