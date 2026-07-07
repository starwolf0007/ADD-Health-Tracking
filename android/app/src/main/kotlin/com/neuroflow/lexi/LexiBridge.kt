package com.neuroflow.lexi

import android.content.Context
import android.os.Build
import com.google.ai.edge.aicore.GenerationConfig
import com.google.ai.edge.aicore.GenerativeModel
import com.google.ai.edge.aicore.generationConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Native Lexi bridge for Android — on-device Gemini Nano via Google's AICore
 * SDK. Exposes a MethodChannel `neuroflow/lexi`:
 *  - isAvailable / checkGeminiNanoAvailable -> real device+model availability
 *    check (never throws; any failure means "not available")
 *  - ping                                   -> "lexi-stub" smoke test
 *  - generate                               -> runs one on-device generation
 *    and returns the model's raw text response, or null on ANY failure
 *
 * BUILD PREREQUISITES — read before wiring this up:
 *   1. `android/app/build.gradle` does not exist in this repo yet (the native
 *      Android project has not been scaffolded — run
 *      `flutter create . --platforms=android,ios --org com.neuroflow` first,
 *      per docs/GOOGLE_SETUP.md §0). This file will not compile until that
 *      exists and the dependencies below are declared in it:
 *        dependencies {
 *            implementation("com.google.ai.edge.aicore:aicore:0.0.1-exp01")
 *            implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
 *        }
 *   2. AICore is an experimental, early-access Google SDK (ai.google.dev/aicore).
 *      It is only actually usable on a small set of devices (Pixel 8 Pro+
 *      class hardware at time of writing) that have the AICore system
 *      component installed. Every call below treats "class present but
 *      device/model unsupported" identically to "class not present" —
 *      isAvailable() and generate() both degrade to false/null rather than
 *      throwing, so the rest of the app is unaffected either way.
 *
 * MANIFEST: no <uses-permission> or <uses-feature> is required for AICore —
 * unlike camera/NFC-style hardware features, AICore availability is entirely
 * a runtime SDK/service check (see MIN_AICORE_SDK_INT below), not a static
 * PackageManager feature flag. See AndroidManifest.xml for the documented
 * decision not to add one.
 */
class LexiBridge : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    // Bound to this plugin's attach/detach lifecycle so no coroutine ever
    // outlives the Flutter engine it was launched from.
    private val bridgeJob = Job()
    private val bridgeScope = CoroutineScope(Dispatchers.Main + bridgeJob)

    // Lazily created on first use; reused across calls while attached.
    // Rebuilt if maxTokens/temperature change between calls.
    private var cachedModel: GenerativeModel? = null
    private var cachedMaxTokens: Int? = null
    private var cachedTemperature: Float? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "neuroflow/lexi")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        bridgeJob.cancel()
        cachedModel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable", "checkGeminiNanoAvailable" -> checkAvailability(result)
            "ping" -> result.success("lexi-stub")
            "generate" -> generate(call, result)
            else -> result.notImplemented()
        }
    }

    // -------------------------------------------------------------------
    // isAvailable / checkGeminiNanoAvailable
    // -------------------------------------------------------------------

    private fun checkAvailability(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < MIN_AICORE_SDK_INT) {
            result.success(false)
            return
        }

        bridgeScope.launch {
            val available = try {
                withContext(Dispatchers.IO) {
                    modelFor(DEFAULT_MAX_TOKENS, DEFAULT_TEMPERATURE).prepareInferenceEngine()
                    true
                }
            } catch (e: Throwable) {
                // Any failure — AICore module not installed, device not
                // eligible, model download not finished, out-of-memory
                // during prep, etc. — means "not available". Never crash.
                false
            }
            result.success(available)
        }
    }

    // -------------------------------------------------------------------
    // generate
    // -------------------------------------------------------------------

    private fun generate(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < MIN_AICORE_SDK_INT) {
            result.success(null)
            return
        }

        val systemPrompt = call.argument<String>("systemPrompt").orEmpty()
        val userMessage = call.argument<String>("userMessage").orEmpty()
        val maxTokens = call.argument<Int>("maxTokens") ?: DEFAULT_MAX_TOKENS
        val temperature = (call.argument<Double>("temperature") ?: DEFAULT_TEMPERATURE.toDouble())
            .toFloat()

        if (userMessage.isBlank()) {
            result.success(null)
            return
        }

        bridgeScope.launch {
            val text = try {
                withContext(Dispatchers.IO) {
                    val model = modelFor(maxTokens, temperature)
                    model.prepareInferenceEngine()

                    val prompt = if (systemPrompt.isBlank()) {
                        userMessage
                    } else {
                        "$systemPrompt\n\n$userMessage"
                    }

                    val response = model.generateContent(prompt)
                    response.candidates.firstOrNull()?.text
                }
            } catch (e: Throwable) {
                // Covers GenerativeAIException, a model that isn't ready yet,
                // OOM, and any other AICore failure. LexiBridge.generate() on
                // the Dart side treats a null result exactly like
                // "unavailable" — no crash, no retry, no user-visible error.
                null
            }
            result.success(text)
        }
    }

    // -------------------------------------------------------------------
    // Model construction
    // -------------------------------------------------------------------

    /**
     * Returns a cached [GenerativeModel] if one already exists for the same
     * (maxTokens, temperature) pair, otherwise builds and caches a new one.
     * Building a GenerativeModel is cheap (it does not itself trigger model
     * download/load — prepareInferenceEngine() does), so re-creating it on a
     * config change is fine.
     */
    private fun modelFor(maxTokens: Int, temperature: Float): GenerativeModel {
        val existing = cachedModel
        if (existing != null && cachedMaxTokens == maxTokens && cachedTemperature == temperature) {
            return existing
        }

        val config: GenerationConfig = generationConfig {
            context = appContext
            this.temperature = temperature
            topK = 16
            maxOutputTokens = maxTokens
        }

        return GenerativeModel(config).also {
            cachedModel = it
            cachedMaxTokens = maxTokens
            cachedTemperature = temperature
        }
    }

    companion object {
        /**
         * AICore (on-device Gemini Nano) ships as a Private Compute Core
         * system component Google has only enabled from Android 14
         * (API 34, UPSIDE_DOWN_CAKE) onward, on devices with an eligible
         * NPU/RAM profile. Every AICore call is gated behind this runtime
         * check instead of raising the app's overall minSdkVersion, because
         * nothing else in NeuroFlow needs API 34 — devices below it simply
         * see Lexi as "unavailable", identical to today's stub behaviour,
         * and every other feature (tasks, routines, habits, sync) keeps
         * working unaffected. This is a runtime check, not a manifest
         * declaration — see the class doc above and AndroidManifest.xml.
         */
        private const val MIN_AICORE_SDK_INT = Build.VERSION_CODES.UPSIDE_DOWN_CAKE // 34

        private const val DEFAULT_MAX_TOKENS = 80
        private const val DEFAULT_TEMPERATURE = 0.7f
    }
}
