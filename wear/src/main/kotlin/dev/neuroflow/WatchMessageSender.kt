// wear/src/main/kotlin/dev/neuroflow/WatchMessageSender.kt
//
// Activity (single-use, no UI) that fires when the user taps Done or Skip
// on the tile. Sends the corresponding message to the paired phone via
// Wearable MessageClient, then finishes immediately.
//
// Why an Activity and not a BroadcastReceiver?
// Tile button click → LaunchAction → Activity is the safest pattern on
// Wear OS 4. BroadcastReceiver works but has lifecycle quirks with tiles.

package dev.neuroflow

import android.app.Activity
import android.os.Bundle
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

class WatchMessageSender : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val path   = intent?.getStringExtra("path")   ?: return finish()
        val taskId = intent?.getStringExtra("taskId") ?: return finish()

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val nodes = Wearable.getNodeClient(applicationContext)
                    .connectedNodes
                    .await()

                val payload = """{"taskId":"$taskId"}""".toByteArray()

                nodes.forEach { node ->
                    Wearable.getMessageClient(applicationContext)
                        .sendMessage(node.id, path, payload)
                        .await()
                }

                // Haptic confirmation — short buzz on success.
                val vibrator = getSystemService(VIBRATOR_SERVICE) as? android.os.Vibrator
                vibrator?.vibrate(android.os.VibrationEffect.createOneShot(80, 200))

            } catch (_: Exception) {
                // Non-fatal — phone may be out of range. Task stays pending.
            } finally {
                finish()
            }
        }
    }
}
