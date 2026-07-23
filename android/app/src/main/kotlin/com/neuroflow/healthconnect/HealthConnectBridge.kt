package com.neuroflow.healthconnect

import androidx.health.connect.client.HealthConnectClient
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Read-only Health Connect platform bridge.
 *
 * This first slice exposes availability only. Android SDK types stay on the
 * native side; Flutter receives a stable string status suitable for mapping to
 * a Dart enum.
 */
class HealthConnectBridge : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailability" -> result.success(getAvailability())
            else -> result.notImplemented()
        }
    }

    private fun getAvailability(): String = try {
        mapSdkStatus(HealthConnectClient.getSdkStatus(binding.applicationContext))
    } catch (_: Exception) {
        // Never expose native exception classes or messages across the channel.
        STATUS_UNSUPPORTED
    }

    companion object {
        private const val CHANNEL = "neuroflow/health_connect"
        internal const val STATUS_AVAILABLE = "available"
        internal const val STATUS_SDK_UNAVAILABLE = "sdkUnavailable"
        internal const val STATUS_PROVIDER_UPDATE_REQUIRED = "providerUpdateRequired"
        internal const val STATUS_UNSUPPORTED = "unsupported"

        internal fun mapSdkStatus(status: Int): String = when (status) {
            HealthConnectClient.SDK_AVAILABLE -> STATUS_AVAILABLE
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
                STATUS_PROVIDER_UPDATE_REQUIRED
            HealthConnectClient.SDK_UNAVAILABLE -> STATUS_SDK_UNAVAILABLE
            else -> STATUS_UNSUPPORTED
        }
    }
}
