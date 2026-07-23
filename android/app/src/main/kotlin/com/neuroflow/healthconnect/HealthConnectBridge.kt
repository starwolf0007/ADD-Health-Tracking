package com.neuroflow.healthconnect

import android.content.Intent
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.WeightRecord
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Read-only Health Connect platform bridge.
 *
 * Android SDK types remain native. Flutter receives stable string values only.
 * Native failures fail closed and never expose exception details across the
 * MethodChannel.
 */
class HealthConnectBridge :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var pluginBinding: FlutterPlugin.FlutterPluginBinding
    private var activityBinding: ActivityPluginBinding? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val permissionContract =
        PermissionController.createRequestPermissionResultContract()
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val pendingGrantedPermissionResults = mutableSetOf<MethodChannel.Result>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingPermissionResult?.success(emptyList<String>())
        pendingPermissionResult = null
        completePendingGrantedPermissionResults()
        scope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        detachActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        detachActivity()
    }

    private fun detachActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        pendingPermissionResult?.success(emptyList<String>())
        pendingPermissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailability" -> result.success(getAvailability())
            "getGrantedPermissions" -> getGrantedPermissions(result)
            "requestPermissions" -> requestPermissions(result)
            else -> result.notImplemented()
        }
    }

    private fun getAvailability(): String = try {
        mapSdkStatus(HealthConnectClient.getSdkStatus(pluginBinding.applicationContext))
    } catch (_: Exception) {
        STATUS_UNSUPPORTED
    }

    private fun getGrantedPermissions(result: MethodChannel.Result) {
        pendingGrantedPermissionResults.add(result)
        scope.launch {
            val granted = safelyGetGrantedPermissions()
            withContext(Dispatchers.Main) {
                // Engine detach completes and removes every pending result first.
                // Only the owner that successfully removes this result may reply.
                if (pendingGrantedPermissionResults.remove(result)) {
                    result.success(toWirePermissionKeys(granted))
                }
            }
        }
    }

    private fun completePendingGrantedPermissionResults() {
        val pending = pendingGrantedPermissionResults.toList()
        pendingGrantedPermissionResults.clear()
        pending.forEach { it.success(emptyList<String>()) }
    }

    private fun requestPermissions(result: MethodChannel.Result) {
        val activity = activityBinding?.activity
        if (activity == null || pendingPermissionResult != null) {
            result.success(emptyList<String>())
            return
        }

        try {
            pendingPermissionResult = result
            val intent = permissionContract.createIntent(activity, REQUIRED_PERMISSIONS)
            activity.startActivityForResult(intent, PERMISSION_REQUEST_CODE)
        } catch (_: Exception) {
            pendingPermissionResult = null
            result.success(emptyList<String>())
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false

        val result = pendingPermissionResult ?: return true
        pendingPermissionResult = null

        val granted = try {
            permissionContract.parseResult(resultCode, data)
        } catch (_: Exception) {
            emptySet()
        }
        result.success(toWirePermissionKeys(granted))
        return true
    }

    private suspend fun safelyGetGrantedPermissions(): Set<String> = try {
        if (HealthConnectClient.getSdkStatus(pluginBinding.applicationContext) !=
            HealthConnectClient.SDK_AVAILABLE
        ) {
            emptySet()
        } else {
            HealthConnectClient
                .getOrCreate(pluginBinding.applicationContext)
                .permissionController
                .getGrantedPermissions()
        }
    } catch (_: Exception) {
        emptySet()
    }

    internal fun mapSdkStatus(status: Int): String = when (status) {
        HealthConnectClient.SDK_AVAILABLE -> STATUS_AVAILABLE
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED ->
            STATUS_PROVIDER_UPDATE_REQUIRED
        HealthConnectClient.SDK_UNAVAILABLE -> STATUS_SDK_UNAVAILABLE
        else -> STATUS_UNSUPPORTED
    }

    internal fun toWirePermissionKeys(granted: Set<String>): List<String> =
        PERMISSION_KEY_BY_VALUE
            .filterKeys { it in granted }
            .values
            .sorted()

    companion object {
        private const val CHANNEL = "neuroflow/health_connect"
        private const val PERMISSION_REQUEST_CODE = 42017

        internal const val STATUS_AVAILABLE = "available"
        internal const val STATUS_SDK_UNAVAILABLE = "sdkUnavailable"
        internal const val STATUS_PROVIDER_UPDATE_REQUIRED = "providerUpdateRequired"
        internal const val STATUS_UNSUPPORTED = "unsupported"

        internal val STEPS_READ_PERMISSION: String =
            HealthPermission.getReadPermission(StepsRecord::class)

        internal val REQUIRED_PERMISSIONS: Set<String> = setOf(
            STEPS_READ_PERMISSION,
            HealthPermission.getReadPermission(HeartRateRecord::class),
            HealthPermission.getReadPermission(RestingHeartRateRecord::class),
            HealthPermission.getReadPermission(SleepSessionRecord::class),
            HealthPermission.getReadPermission(ExerciseSessionRecord::class),
            HealthPermission.getReadPermission(WeightRecord::class),
        )

        private val PERMISSION_KEY_BY_VALUE: Map<String, String> = mapOf(
            STEPS_READ_PERMISSION to "steps",
            HealthPermission.getReadPermission(HeartRateRecord::class) to "heartRate",
            HealthPermission.getReadPermission(RestingHeartRateRecord::class) to
                "restingHeartRate",
            HealthPermission.getReadPermission(SleepSessionRecord::class) to "sleep",
            HealthPermission.getReadPermission(ExerciseSessionRecord::class) to "exercise",
            HealthPermission.getReadPermission(WeightRecord::class) to "weight",
        )
    }
}
