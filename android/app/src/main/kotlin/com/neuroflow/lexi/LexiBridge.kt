package com.neuroflow.lexi

import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

import com.google.ai.edge.aicore.GenerativeAIException
import com.google.ai.edge.aicore.GenerativeModel
import com.google.ai.edge.aicore.generationConfig

/**
 * LexiBridge — native side of the on-device LLM seam (spec §14).
 *
 * Backed by Google's AI Edge SDK / AICore (Gemini Nano):
 *   implementation("com.google.ai.edge.aicore:aicore:0.0.1-exp01")
 * The dependency + manifest additions live in
 * lib/intelligence/GRADLE_AICORE_SETUP.md because this repo's
 * android/app/build.gradle does not exist yet (`flutter create` generates
 * it) — apply that doc's Gradle snippet once it does. The AndroidManifest.xml
 * `<uses-feature>` addition from that doc has already been applied in this
 * repo (see android/app/src/main/AndroidManifest.xml).
 *
 * ⚠️ REALITY CHECK (documented, not hidden):
 *   • AI Edge SDK is Google's EXPERIMENTAL developer preview. Google's own
 *     blog: "experimental access is for development purposes, and is not for
 *     production usage at this time." APIs may change between exp releases.
 *   • Device support for text-to-text via AICore began with the Pixel 9
 *     series. Emulators are NOT supported — physical hardware only.
 *   • AICore requires Android 14 QPR1+; we gate on API 34 before touching
 *     any AICore class so older OS builds can never hit a missing-class path.
 *   Net effect: isAvailable() returns false on most devices today. That is
 *   correct behavior — the entire PlanAdvisor seam is designed so the app is
 *   100% functional with Lexi silently absent (NoOp fallback, DEC-003).
 *
 * AVAILABILITY STRATEGY: the official exp01 reference documents
 * `suspend fun prepareInferenceEngine()` — "prepares engine in advance…
 * strictly optional, but recommended." It throws GenerativeAIException when
 * the runtime/model can't serve. We use successful preparation as the
 * availability signal: if the engine warms, it's genuinely available; any
 * throw means "not available," full stop. We deliberately do NOT trigger a
 * model download from here — a multi-GB background fetch without consent
 * violates this app's own calm/no-surprise principles. If the model isn't
 * already on-device, we report unavailable.
 *
 * CONTRACT (must match lib/intelligence/lexi_plan_advisor.dart exactly):
 *   checkGeminiNanoAvailable() -> Bool
 *   generateResponse({systemPrompt, userMessage, maxTokens, temperature}) -> String?
 *       Raw model text, or null on any failure. Timeout (5s) surfaces as a
 *       PlatformException("LEXI_TIMEOUT") — Dart's catch-all resolves both
 *       null and exceptions to the same silent keep-the-deterministic-plan
 *       path, so the user never sees a crash, stall, or empty reason.
 *
 * NOTE on per-call maxTokens/temperature: exp01 fixes generation config at
 * model construction. The per-call arguments are honored on FIRST model
 * construction and advisory thereafter; defaults are tuned for Lexi's short
 * JSON replies. Documented here so nobody mistakes it for a dropped wire.
 *
 * Legacy dev smoke-test methods kept: isAvailable(), ping().
 */
class LexiBridge : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    // Supervisor scope: one failed call can't cancel siblings; not tied to
    // any Activity lifecycle (plugin outlives config changes).
    private val scope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())

    // Created once, reused. Volatile not needed: only touched on main dispatcher.
    private var model: GenerativeModel? = null

    // True after one successful prepareInferenceEngine() this process.
    private var engineReady: Boolean = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "neuroflow/lexi")
        channel.setMethodCallHandler(this)
        appContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        model = null
        engineReady = false
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkGeminiNanoAvailable" -> scope.launch {
                result.success(ensureEngineReady())
            }

            "generateResponse" -> {
                val systemPrompt = call.argument<String>("systemPrompt")
                val userMessage = call.argument<String>("userMessage")
                val maxTokens = call.argument<Int>("maxTokens") ?: 120
                val temperature = (call.argument<Double>("temperature") ?: 0.7).toFloat()

                if (userMessage.isNullOrBlank()) {
                    result.success(null)
                    return
                }

                scope.launch {
                    try {
                        if (!ensureEngineReady(maxTokens, temperature)) {
                            result.success(null)
                            return@launch
                        }
                        val text = withTimeout(5_000L) {
                            runInference(systemPrompt, userMessage)
                        }
                        result.success(text)
                    } catch (e: TimeoutCancellationException) {
                        // The one surfaced error, per spec. Dart still folds
                        // this into the same silent fallback.
                        result.error("LEXI_TIMEOUT", "Gemini Nano inference exceeded 5s", null)
                    } catch (e: Exception) {
                        // Anything else — never crash past this boundary.
                        result.success(null)
                    }
                }
            }

            // --- Legacy dev smoke-test methods ---
            "isAvailable" -> scope.launch { result.success(ensureEngineReady()) }
            "ping" -> result.success("lexi-live")

            else -> result.notImplemented()
        }
    }

    /**
     * True only when the AICore engine has been successfully prepared in this
     * process. Never throws. API-34 gate runs BEFORE any AICore class is
     * referenced, so pre-QPR1 devices can't hit a class-resolution path.
     */
    private suspend fun ensureEngineReady(
        maxTokens: Int = 120,
        temperature: Float = 0.7f,
    ): Boolean {
        if (Build.VERSION.SDK_INT < 34) return false
        if (engineReady) return true

        return try {
            val m = model ?: GenerativeModel(
                generationConfig = generationConfig {
                    context = appContext
                    maxOutputTokens = maxTokens.coerceIn(16, 256)
                    this.temperature = temperature.coerceIn(0f, 1f)
                    topK = 16
                }
            ).also { model = it }

            m.prepareInferenceEngine()
            engineReady = true
            true
        } catch (e: GenerativeAIException) {
            // Unsupported device, model not downloaded, AICore absent…
            engineReady = false
            false
        } catch (e: Exception) {
            engineReady = false
            false
        }
    }

    /**
     * One inference. Caller owns the 5s timeout — exactly one timeout
     * boundary to reason about. Returns trimmed text or null.
     */
    private suspend fun runInference(
        systemPrompt: String?,
        userMessage: String,
    ): String? {
        val m = model ?: return null
        val fullPrompt = if (systemPrompt.isNullOrBlank()) {
            userMessage
        } else {
            "$systemPrompt\n\n$userMessage"
        }
        return try {
            m.generateContent(fullPrompt).text?.trim()
        } catch (e: GenerativeAIException) {
            null
        }
    }
}
