// wear/src/main/kotlin/dev/neuroflow/WearDataReceiver.kt
//
// Listens for DataItem changes pushed from the phone via the Wearable
// Data Layer. When /neuroflow/primary arrives, stores it in WearStateStore
// and requests a tile refresh so the user sees the new task immediately.

package dev.neuroflow

import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import androidx.wear.tiles.TileService

class WearDataReceiver : WearableListenerService() {

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents.forEach { event ->
            if (event.type == DataEvent.TYPE_CHANGED &&
                event.dataItem.uri.path == "/neuroflow/primary"
            ) {
                val dataMap = DataMapItem.fromDataItem(event.dataItem).dataMap
                val pushedAt = dataMap.getLong("pushedAt", 0L)

                // Ignore stale pushes older than 10 minutes.
                if (System.currentTimeMillis() - pushedAt > 10 * 60 * 1000L) return

                WearStateStore.update(
                    taskId       = dataMap.getString("taskId", ""),
                    taskTitle    = dataMap.getString("taskTitle", ""),
                    quickWinCount = dataMap.getInt("quickWinCount", 0),
                    pendingCount = dataMap.getInt("pendingCount", 0),
                    hasPrimaryTask = dataMap.getBoolean("hasPrimaryTask", false),
                    pushedAt     = pushedAt,
                )

                // Ask the tile to re-render with the fresh data.
                TileService.getUpdater(applicationContext)
                    .requestUpdate(NeuroFlowTile::class.java)
            }
        }
    }
}
