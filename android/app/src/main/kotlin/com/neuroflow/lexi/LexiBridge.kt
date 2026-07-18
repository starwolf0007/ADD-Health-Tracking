package com.neuroflow.lexi

import android.util.Log
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
 * Real SDK integration: aicore (com.google.ai.edge.aicore) is already on the
 * classpath (build.gradle.kts). Drop the real calls into the TODO anchors
 * marked "AICORE" when the API stabilises.
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

    /**
     * Dedicated IO scope for model init, warm-up, and inference.
     * SupervisorJob ensures one failed child does not cancel siblings.
     */
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    @Volatile private var lifecycleState = LifecycleState.UNINITIALIZED

    /**
     * The retained inference session. Created once during warm-up and reused
     * for all subsequent [generateResponse] calls.
     *
     * TODO [AICORE]: replace Any? with the real session type, e.g.:
     *   private var session: GenerativeModel? = null
     */
    private var session: Any? = null

    // ── FlutterPlugin ────────────────────────────────────────────────────────

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
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

                // TODO [AICORE]: initialize the real model, e.g.:
                //   val config = generationConfig { temperature = 0.7f }
                //   val model = GenerativeModel(
                //     modelName = "gemini-nano",
                //     generationConfig = config,
                //   )

                lifecycleState = LifecycleState.WARMING
                Log.d(TAG, "Warm: pre-loading model weights")

                // TODO [AICORE]: call model.warmUp() or equivalent:
                //   model.warmUp()

                session = createStubSession()   // TODO [AICORE]: session = model
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

        // TODO [AICORE]: release native resources, e.g.:
        //   (session as? GenerativeModel)?.close()

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
        Log.d(TAG, "runInference: prompt length=${prompt.length}, session=$session")

        // TODO [AICORE]: replace with real call, e.g.:
        //   return (session as GenerativeModel)
        //       .generateContent(prompt)
        //       .text

        return null   // stub: no on-device LLM wired yet
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun isReady(): Boolean = lifecycleState == LifecycleState.READY

    /** Placeholder session object. Remove when real SDK session is wired. */
    private fun createStubSession(): Any = object : Any() {
        override fun toString() = "LexiStubSession"
    }

    // ── Constants ─────────────────────────────────────────────────────────────

    companion object {
        private const val CHANNEL = "neuroflow/lexi"
        private const val TAG = "LexiBridge"
    }
}
