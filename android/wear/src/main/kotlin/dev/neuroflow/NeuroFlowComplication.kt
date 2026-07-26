// wear/src/main/kotlin/dev/neuroflow/NeuroFlowComplication.kt
//
// Wear OS complication — RANGED_VALUE arc showing pending task count.
//
// Per spec §6:
//   Value:      pendingCount (0–20, clamped)
//   Short text: count as string
//   Long text:  "tasks left"
//   Tap action: opens NeuroFlowTile (LaunchAction)
//
// Updates automatically when WearDataReceiver stores new state and calls
// ComplicationDataSourceUpdateRequester.

package dev.neuroflow

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest

class NeuroFlowComplication : ComplicationDataSourceService() {

    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        if (type != ComplicationType.RANGED_VALUE) return null
        return buildComplicationData(pendingCount = 3)
    }

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener,
    ) {
        val state = WearStateStore.current
        listener.onComplicationData(buildComplicationData(state.pendingCount))
    }

    private fun buildComplicationData(pendingCount: Int): RangedValueComplicationData {
        // Dynamic ceiling: at least 10 so the arc doesn't look full when there
        // are only 1-2 tasks. Grows naturally once the user has 11+ tasks.
        val arcMax  = maxOf(pendingCount, 10).toFloat()
        val clamped = pendingCount.coerceIn(0, arcMax.toInt())
        val tapIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, WatchMessageSender::class.java), // placeholder — deep-link to tile
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        return RangedValueComplicationData.Builder(
            value        = clamped.toFloat(),
            min          = 0f,
            max          = arcMax,
            contentDescription = PlainComplicationText.Builder("Tasks pending").build(),
        )
            .setText(PlainComplicationText.Builder(clamped.toString()).build())
            .setTitle(PlainComplicationText.Builder("tasks left").build())
            .setTapAction(tapIntent)
            .build()
    }
}
