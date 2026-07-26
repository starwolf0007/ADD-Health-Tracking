// android/app/src/main/kotlin/dev/neuroflow/AlarmBridge.kt
//
// Registers the 'neuroflow/alarms' MethodChannel on the phone side.
// Called from MainActivity.configureFlutterEngine() alongside WearBridge.
//
// Flutter side: lib/platform/alarms/alarm_scheduler.dart
//   AlarmScheduler.scheduleMorning(hour, minute) → invokeMethod('scheduleMorning', {...})
//   AlarmScheduler.cancelMorning()               → invokeMethod('cancelMorning')
//
// Kotlin side: delegates to ExactAlarmScheduler.schedule() / .cancel()

package dev.neuroflow

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object AlarmBridge {

    private const val CHANNEL = "neuroflow/alarms"

    /**
     * Register the MethodChannel on the given messenger.
     * Call from MainActivity.configureFlutterEngine().
     */
    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            handleCall(call, result, context)
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result, context: Context) {
        when (call.method) {
            "scheduleMorning" -> {
                val hour   = call.argument<Int>("hour")   ?: 8
                val minute = call.argument<Int>("minute") ?: 0
                try {
                    ExactAlarmScheduler.schedule(context, hour, minute)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ALARM_SCHEDULE_FAILED", e.message, null)
                }
            }

            "cancelMorning" -> {
                try {
                    ExactAlarmScheduler.cancel(context)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("ALARM_CANCEL_FAILED", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }
}
