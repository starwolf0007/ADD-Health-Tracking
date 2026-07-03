package com.neuroflow.lexi

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * LexiBridge — native side of the on-device LLM seam (spec §14).
 *
 * Exposes MethodChannel `neuroflow/lexi`.
 *
 * CONTRACT (must match lib/intelligence/lexi_plan_advisor.dart exactly):
 *   checkGeminiNanoAvailable() -> Bool
 *       True only when the AICore / Gemini Nano runtime is present and warm.
 *       Stubbed false until the SDK is integrated.
 *   generateResponse({systemPrompt, userMessage, maxTokens, temperature}) -> String?
 *       Returns the model's text, or null when unavailable. Dart treats null
 *       as "no refinement" and falls back to the deterministic plan silently.
 *
 * Legacy test methods (kept for adb/dev smoke tests, not used by the app):
 *   isAvailable() -> Bool, ping() -> String
 *
 * HISTORY NOTE: an earlier version of this file only handled ping/isAvailable
 * while the Dart advisor called checkGeminiNanoAvailable/generateResponse —
 * the two halves were written against different contracts. The Dart names win
 * because the full advisor logic lives there. Do not rename on either side
 * without changing both in the same commit.
 */
class LexiBridge : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "neuroflow/lexi")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // --- Real contract (what LexiPlanAdvisor calls) ---
            "checkGeminiNanoAvailable" -> {
                // TODO(sdk): query AICore availability once the Gemini Nano
                // SDK is added. Until then: honestly unavailable.
                result.success(false)
            }
            "generateResponse" -> {
                // TODO(sdk): call Gemini Nano with call.argument<String>("systemPrompt"),
                // "userMessage", "maxTokens", "temperature". Null = graceful NoOp fallback.
                result.success(null)
            }

            // --- Legacy dev smoke-test methods ---
            "isAvailable" -> result.success(false)
            "ping" -> result.success("lexi-stub")

            else -> result.notImplemented()
        }
    }
}
