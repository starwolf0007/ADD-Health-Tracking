// lib/intelligence/lexi_bridge.dart
//
// Dart-side wrapper for the 'neuroflow/lexi' MethodChannel.
// Calls the native Lexi bridge registered in:
//   android: com.neuroflow.lexi.LexiBridge (Kotlin, on-device AICore/Gemini Nano)
//
// All methods are fully guarded — if the native side is absent, missing,
// slow, or throws, they return a safe default value and never propagate an
// exception into the caller. LexiPlanAdvisor is the only caller — never call
// this directly from UI (§14 AI tiering).

import 'package:flutter/services.dart';

class LexiBridge {
  static const _channel = MethodChannel('neuroflow/lexi');

  /// Dart-side ceiling on any single native call. On-device inference can
  /// stall (cold model load, device under memory pressure); this guarantees
  /// every call below returns within 5s regardless of what the native side
  /// does, so a Lexi call can never leave the UI spinner-stalled.
  static const _callTimeout = Duration(seconds: 5);

  /// Returns true if a native on-device LLM is available and responsive.
  /// Returns false on any error, timeout, or if the channel is not registered.
  static Future<bool> isAvailable() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isAvailable').timeout(_callTimeout);
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Smoke-test ping. Returns 'lexi-stub' from the Kotlin stub, or
  /// 'unavailable' on any error, timeout, or missing plugin.
  static Future<String> ping() async {
    try {
      final result =
          await _channel.invokeMethod<String>('ping').timeout(_callTimeout);
      return result ?? 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  /// Runs one on-device generation and returns the model's raw text response
  /// (expected to be a JSON string — see LexiConfig.systemPrompt), or null on
  /// ANY failure: the 5-second timeout enforced here, a PlatformException
  /// from the native side, a missing plugin, or anything else the channel
  /// could throw. Callers must treat null exactly like "Lexi had nothing to
  /// add" — never retry, never surface the failure to the user.
  static Future<String?> generate({
    required String systemPrompt,
    required String userMessage,
    int maxTokens = 80,
    double temperature = 0.7,
  }) async {
    try {
      final result = await _channel.invokeMethod<String>('generate', {
        'systemPrompt': systemPrompt,
        'userMessage': userMessage,
        'maxTokens': maxTokens,
        'temperature': temperature,
      }).timeout(_callTimeout);
      return result;
    } catch (_) {
      // Covers TimeoutException, PlatformException, MissingPluginException,
      // and any other error the platform channel could raise. Silent by
      // design — see LexiPlanAdvisor.refine() for the caller-side contract.
      return null;
    }
  }
}
