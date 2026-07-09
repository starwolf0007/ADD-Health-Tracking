// lib/intelligence/lexi_bridge.dart
//
// Dart-side wrapper for the 'neuroflow/lexi' MethodChannel.
// Calls the native Lexi bridge stub registered in:
//   android: com.neuroflow.lexi.LexiBridge (Kotlin)
//
// All methods are fully guarded — if the native side is absent, missing, or
// throws, they return a safe default value and never propagate exceptions into
// the caller. This means the app can compile and run without the native Lexi
// implementation being complete.
//
// When Lexi (on-device LLM) is implemented, add methods here and mirror them
// in LexiBridge.kt. Keep PlanAdvisor as the only caller — never call this
// directly from UI.

import 'package:flutter/services.dart';

import 'package:neuroflow/platform/error_reporter.dart';

class LexiBridge {
  static const _channel = MethodChannel('neuroflow/lexi');

  /// Returns true if a native on-device LLM is available and responsive.
  /// Returns false on any error or if the channel is not registered.
  static Future<bool> isAvailable() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException catch (error, stackTrace) {
      reportNonFatalError(
        'Failed to query Lexi availability',
        error,
        stackTrace,
      );
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Smoke-test ping. Returns 'lexi-stub' from the Kotlin stub,
  /// or 'unavailable' if bridge is absent.
  static Future<String> ping() async {
    try {
      final result = await _channel.invokeMethod<String>('ping');
      return result ?? 'unavailable';
    } on MissingPluginException {
      return 'unavailable';
    } catch (error, stackTrace) {
      reportNonFatalError('Failed to ping Lexi', error, stackTrace);
      return 'unavailable';
    }
  }

  // ── Phase 2 placeholders (not yet implemented in Kotlin) ──────────────────
  //
  // static Future<String?> refinePlan(Map<String, dynamic> context) async { ... }
  // static Future<String?> suggestSubtasks(String taskTitle) async { ... }
}
