// android/app/src/main/kotlin/dev/neuroflow/WearBridge.kt
//
// Phone-side bridge between Flutter and the Wearable Data Layer.
//
// Responsibilities:
//   1. Receives Flutter MethodChannel calls (channel: 'neuroflow/wear')
//      and pushes DataItems to the watch via Wearable.getDataClient().
//   2. Listens for MessageClient messages from the watch (/neuroflow/complete,
//      /neuroflow/snooze) and calls Flutter back via the same MethodChannel.
//
// Registered in MainActivity.configureFlutterEngine().
//
// Thread safety: MethodChannel calls arrive on the main thread.
// Data Layer callbacks arrive on a background thread — post to main before
// calling Flutter.

package dev.neuroflow

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import org.json.JSONObject

private const val CHANNEL  = "neuroflow/wear"
private const val PATH_PRIMARY  = "/neuroflow/primary"
private const val PATH_COMPLETE = "/neuroflow/complete"
private const val PATH_SNOOZE   = "/neuroflow/snooze"
private const val TAG = "WearBridge"

/**
 * Call this from MainActivity.configureFlutterEngine() to wire the channel.
 *
 * ```kotlin
 * WearBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
 * ```
 */
object WearBridge {

    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(Dispatchers.IO)

    // Kept so WearPhoneMessageReceiver can call back to Flutter.
    var channel: MethodChannel? = null
        private set

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger, context: android.content.Context) {
        val ch = MethodChannel(messenger, CHANNEL)
        channel = ch

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "pushPrimaryTask" -> {
                    val args = call.arguments as? Map<*, *> ?: return@setMethodCallHandler result.error(
                        "INVALID_ARGUMENTS",
                        "pushPrimaryTask requires a map",
                        null,
                    )
                    scope.launch {
                        try {
                            pushToWatch(context, args)
                            mainHandler.post { result.success(null) }
                        } catch (error: Exception) {
                            Log.w(TAG, "Failed to push primary task to Wear OS", error)
                            mainHandler.post {
                                result.error("WEAR_PUSH_FAILED", error.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private suspend fun pushToWatch(context: android.content.Context, args: Map<*, *>) {
        val request = PutDataMapRequest.create(PATH_PRIMARY).apply {
            dataMap.putString("taskId",       args["taskId"]       as? String ?: "")
            dataMap.putString("taskTitle",    args["taskTitle"]    as? String ?: "")
            dataMap.putInt("quickWinCount",   (args["quickWinCount"] as? Int) ?: 0)
            dataMap.putInt("pendingCount",    (args["pendingCount"]  as? Int) ?: 0)
            dataMap.putBoolean("hasPrimaryTask", (args["hasPrimaryTask"] as? Boolean) ?: false)
            dataMap.putLong("pushedAt",       (args["pushedAt"]    as? Long) ?: System.currentTimeMillis())
        }.asPutDataRequest().setUrgent() // urgent = low-latency delivery

        Wearable.getDataClient(context).putDataItem(request).await()
    }

    /** Called by WearPhoneMessageReceiver when a watch message arrives. */
    fun onWatchMessage(path: String, taskId: String) {
        val method = when (path) {
            PATH_COMPLETE -> "onWatchComplete"
            PATH_SNOOZE   -> "onWatchSnooze"
            else          -> return
        }
        mainHandler.post {
            channel?.invokeMethod(
                method,
                mapOf("taskId" to taskId),
                object : MethodChannel.Result {
                    override fun success(result: Any?) = Unit

                    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                        Log.w(TAG, "Flutter rejected watch action $method: $errorCode $errorMessage")
                    }

                    override fun notImplemented() {
                        Log.w(TAG, "Flutter did not implement watch action $method")
                    }
                },
            )
        }
    }
}

/**
 * WearableListenerService that receives messages from the watch and
 * forwards them to Flutter via WearBridge.
 *
 * Register in android/app/src/main/AndroidManifest.xml:
 *
 * <service
 *     android:name=".WearPhoneMessageReceiver"
 *     android:exported="true">
 *   <intent-filter>
 *     <action android:name="com.google.android.gms.wearable.MESSAGE_RECEIVED"/>
 *     <data android:scheme="wear" android:host="*" android:pathPrefix="/neuroflow"/>
 *   </intent-filter>
 * </service>
 */
class WearPhoneMessageReceiver : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (!event.path.startsWith("/neuroflow")) return
        try {
            val json    = JSONObject(String(event.data))
            val taskId  = json.optString("taskId", "")
            WearBridge.onWatchMessage(event.path, taskId)
        } catch (error: Exception) {
            Log.w("WearPhoneMessageReceiver", "Ignoring malformed watch payload", error)
        }
    }
}
