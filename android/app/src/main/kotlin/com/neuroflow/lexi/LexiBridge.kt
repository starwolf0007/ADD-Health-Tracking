package com.neuroflow.lexi

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Simple Lexi bridge stub for Android.
 * Exposes a MethodChannel `neuroflow/lexi` with a couple of safe test methods:
 *  - isAvailable -> returns false (real on-device LLM not implemented)
 *  - ping -> returns "lexi-stub"
 *
 * This file intentionally does not implement real LLM functionality. It's a
 * lightweight native-side placeholder so Dart can call the channel without
 * crashing if you later add platform code.
 */
class LexiBridge: FlutterPlugin, MethodChannel.MethodCallHandler {
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
            "checkGeminiNanoAvailable" -> result.success(false) // stub: no native LLM yet
            "generateResponse" -> result.success(null) // stub: no native LLM yet
            "isAvailable" -> result.success(false)
            "ping" -> result.success("lexi-stub")
            else -> result.notImplemented()
        }
    }
}
