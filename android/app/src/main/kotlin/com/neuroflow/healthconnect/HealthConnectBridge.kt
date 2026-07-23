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
import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Read-only Health Connect platform bridge.
 *
 * Android SDK types remain native. Flutter receives stable primitive transport
 * values only. Native failures fail closed and never expose exception details.
 */
class HealthConnectBridge :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    private lateinit var channel: MethodChannel
    private lateinit var pluginBinding: FlutterPlugin.FlutterPluginBinding
    private var activityBinding: ActivityPluginBinding? = null
    private var scope: CoroutineScope = newScope()

    private val permissionContract =
        PermissionController.createRequestPermissionResultContract()
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val pendingGrantedPermissionResults = mutableSetOf<MethodChannel.Result>()
    private val pendingStepsResults = mutableSetOf<MethodChannel.Result>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        pluginBinding = binding
        scope = newScope()
        channel = MethodChannel(binding.binaryMessenger, CHANNEL)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        pendingPermissionResult?.success(emptyList<String>())
        pendingPermissionResult = null
        completePendingGrantedPermissionResults()
        completePendingStepsResults()
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
            "readSteps" -> readSteps(call, result)
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

    private fun readSteps(call: MethodCall, result: MethodChannel.Result) {
        val startEpochMs = (call.argument<Number>("startInclusiveEpochMs"))?.toLong()
        val endEpochMs = (call.argument<Number>("endExclusiveEpochMs"))?.toLong()
        if (startEpochMs == null || endEpochMs == null || endEpochMs <= startEpochMs) {
            result.success(readEnvelope(READ_FAILED))
            return
        }

        pendingStepsResults.add(result)
        scope.launch {
            val envelope = try {
                val sdkStatus = HealthConnectClient.getSdkStatus(pluginBinding.applicationContext)
                if (sdkStatus != HealthConnectClient.SDK_AVAILABLE) {
                    readEnvelope(READ_UNAVAILABLE)
                } else {
                    val client = HealthConnectClient.getOrCreate(pluginBinding.applicationContext)
                    val granted = client.permissionController.getGrantedPermissions()
                    if (STEPS_READ_PERMISSION !in granted) {
                        readEnvelope(READ_PERMISSION_DENIED)
                    } else {
                        val records = HealthConnectStepsReader(client).readAll(
                            startInclusive = Instant.ofEpochMilli(startEpochMs),
                            endExclusive = Instant.ofEpochMilli(endEpochMs),
                        )
                        readEnvelope(READ_OK, records)
                    }
                }
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (_: SecurityException) {
                readEnvelope(READ_PERMISSION_DENIED)
            } catch (_: Exception) {
                readEnvelope(READ_FAILED)
            }

            withContext(Dispatchers.Main) {
                if (pendingStepsResults.remove(result)) {
                    result.success(envelope)
                }
            }
        }
    }

    private fun completePendingStepsResults() {
        val pending = pendingStepsResults.toList()
        pendingStepsResults.clear()
        val envelope = readEnvelope(READ_FAILED)
        pending.forEach { it.success(envelope) }
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
    } catch (cancellation: CancellationException) {
        throw cancellation
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

        internal const val READ_OK = "ok"
        internal const val READ_UNAVAILABLE = "unavailable"
        internal const val READ_PERMISSION_DENIED = "permission_denied"
        internal const val READ_FAILED = "failed"

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

        private fun newScope(): CoroutineScope =
            CoroutineScope(SupervisorJob() + Dispatchers.IO)

        internal fun readEnvelope(
            status: String,
            records: List<Map<String, Any?>> = emptyList(),
        ): Map<String, Any?> = mapOf(
            "status" to status,
            "records" to if (status == READ_OK) records else emptyList<Map<String, Any?>>(),
        )
    }
}
