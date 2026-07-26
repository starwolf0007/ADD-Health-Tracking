package com.neuroflow.lexi

import android.content.Context
import android.util.Log
import com.google.ai.edge.aicore.GenerativeModel
import com.google.ai.edge.aicore.generationConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*

/**
 * LexiBridge — NeuroFlow native AI bridge (Stage 5: lifecycle refactor).
 *
 * Lifecycle:  Initialize → Warm → Reuse Session → Dispose
 *
 * The Gemini Nano inference session is created ONCE in [onAttachedToEngine],
 * warmed up in the background, and then reused for every [generateResponse]
 * call. This avoids the per-call model-load overhead that existed in the
 * previous implementation.
 *
 * Real SDK integration: com.google.ai.edge.aicore:aicore:0.0.1-exp01
 * (build.gradle.kts). `generationConfig`/`temperature`/`maxOutputTokens` are
 * fixed at model-construction time (the SDK has no per-call override), so
 * they're set once here to match the only values the Dart side ever sends
 * (see LexiPlanAdvisor._callOnDeviceLLM: maxTokens 80, temperature 0.7).
 * DownloadConfig is left at its default (no custom DownloadCallback) — there
 * is no UI surface for model-download progress in this sprint; a failed or
 * pending download simply falls through the existing catch block below and
 * Lexi stays unavailable, per ADR-001/ADR-006 (AI absent must never block
 * the app).
 *
 * Channel: neuroflow/lexi
 * Methods:
 *   checkGeminiNanoAvailable → Boolean
 *   generateResponse(prompt: String) → String?
 *   isAvailable → Boolean
 *   ping → String
 */
class LexiBridge : FlutterPlugin, MethodChannel.MethodCallHandler {

    // ── Lifecycle state machine ──────────────────────────────────────────────
    private enum class LifecycleState {
        UNINITIALIZED,
        INITIALIZING,
        WARMING,
        READY,
        DISPOSED,
    }

    // ── Fields ───────────────────────────────────────────────────────────────

    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    /**
     * Dedicated IO scope for model init, warm-up, and inference.
     * SupervisorJob ensures one failed child does not cancel siblings.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile private var lifecycleState = LifecycleState.UNINITIALIZED

    /**
     * The retained inference session. Created once during warm-up and reused
     * for all subsequent [generateResponse] calls.
     */
    private var session: GenerativeModel? = null

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
        appContext = binding.applicationContext
        initializeAndWarm()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        dispose()
    }

    // ── MethodCallHandler ────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkGeminiNanoAvailable" -> result.success(isReady())
            "isAvailable"             -> result.success(isReady())
            "generateResponse"        -> handleGenerate(call, result)
            "ping"                    -> result.success("lexi-stub")
            else                      -> result.notImplemented()
        }
    }

    // ── Lifecycle implementation ──────────────────────────────────────────────

    /**
     * Phase 1 — Initialize: allocate inference engine resources.
     * Phase 2 — Warm:       pre-load model weights so first inference has no
     *                        cold-start latency.
     *
     * Runs entirely on [Dispatchers.IO]; never blocks the Flutter main thread.
     */
    private fun initializeAndWarm() {
        if (lifecycleState != LifecycleState.UNINITIALIZED) return
        lifecycleState = LifecycleState.INITIALIZING

        scope.launch {
            try {
                Log.d(TAG, "Initialize: setting up inference engine")

                val config = generationConfig {
                    context = appContext
                    temperature = 0.7f
                    maxOutputTokens = 80
                }
                val model = GenerativeModel(config)

                lifecycleState = LifecycleState.WARMING
                Log.d(TAG, "Warm: preparing inference engine")

                // Triggers device-capability/model-availability checks and, if
                // needed, a model download — throws (PreparationException /
                // DownloadException / etc., all GenerativeAIException) on any
                // device that can't run Gemini Nano. Caught below; Lexi simply
                // stays unavailable, matching the pre-existing fallback
                // contract (ADR-001/ADR-006).
                model.prepareInferenceEngine()

                session = model
                lifecycleState = LifecycleState.READY
                Log.d(TAG, "Ready: inference session live, state=$lifecycleState")

            } catch (e: Exception) {
                Log.e(TAG, "Lifecycle init failed — will retry on next attach", e)
                lifecycleState = LifecycleState.UNINITIALIZED
            }
        }
    }

    /**
     * Dispose: tears down the retained session and cancels the coroutine scope.
     * Guaranteed to run when the Flutter engine detaches.
     */
    private fun dispose() {
        lifecycleState = LifecycleState.DISPOSED

        session?.close()
        session = null
        scope.cancel()
        Log.d(TAG, "Disposed: inference session released")
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    private fun handleGenerate(call: MethodCall, result: MethodChannel.Result) {
        // Guard: still warming up or unavailable — return null gracefully.
        if (!isReady()) {
            Log.d(TAG, "generateResponse called while state=$lifecycleState — returning null")
            result.success(null)
            return
        }

        val prompt = call.argument<String>("prompt")
            ?: buildString {
                call.argument<String>("systemPrompt")?.let {
                    append(it)
                    append("\n\n")
                }
                call.argument<String>("userMessage")?.let { append(it) }
            }.takeIf { it.isNotBlank() }
            ?: run {
            result.error(
                "INVALID_ARG",
                "prompt or systemPrompt/userMessage arguments are required",
                null,
            )
            return
        }

        // Dispatch inference to IO; post result back on the main thread so
        // Flutter's MethodChannel contract is satisfied.
        scope.launch {
            try {
                val response = runInference(prompt)
                withContext(Dispatchers.Main) { result.success(response) }
            } catch (e: Exception) {
                Log.e(TAG, "Inference error", e)
                withContext(Dispatchers.Main) {
                    result.error("INFERENCE_ERROR", e.message, null)
                }
            }
        }
    }

    /**
     * Runs a single inference turn on the REUSED [session].
     * No new session is created per call — this is the core of the Stage 5
     * lifecycle optimisation.
     */
    private suspend fun runInference(prompt: String): String? {
        val model = session ?: return null
        Log.d(TAG, "runInference: prompt length=${prompt.length}")
        return model.generateContent(prompt).text
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun isReady(): Boolean = lifecycleState == LifecycleState.READY

    // ── Constants ─────────────────────────────────────────────────────────────

    companion object {
        private const val CHANNEL = "neuroflow/lexi"
        private const val TAG = "LexiBridge"
    }
}
