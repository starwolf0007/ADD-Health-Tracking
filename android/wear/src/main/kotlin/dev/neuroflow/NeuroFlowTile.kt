// wear/src/main/kotlin/dev/neuroflow/NeuroFlowTile.kt
//
// Wear OS 4 TileService — the primary interaction surface on Pixel Watch 4.
//
// Renders a single-screen tile (no scroll) showing the current primary task
// with two actions: Done (✓) and Skip ("Too hard right now").
//
// Layout per spec §5:
//   App name label (muted)
//   Task title (large, 2-line max)
//   [Done] [Skip] action buttons
//
// Empty state: "You're clear. Rest." — no action buttons.
// Stale/offline state: "Open phone to refresh." — no action buttons.
//
// Action flow:
//   Done tap  → sends /neuroflow/complete message to phone via MessageClient
//   Skip tap  → sends /neuroflow/snooze  message to phone via MessageClient
//   Phone receives message → updates TaskRepository → pushes new DataItem
//   WearDataReceiver picks up new DataItem → requests tile refresh

package dev.neuroflow

import android.content.Context
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders.*
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.expression.ActionBuilders.AndroidActivity
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.android.gms.wearable.Wearable
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

// Brand colors from spec §13
private const val COLOR_BACKGROUND = 0xFF0C0C0D.toInt()
private const val COLOR_TEXT_PRIMARY = 0xFFE8E8EA.toInt()
private const val COLOR_TEXT_MUTED = 0xFF6B6B70.toInt()
private const val COLOR_ACCENT = 0xFF2FB083.toInt()   // Done button
private const val COLOR_SURFACE = 0xFF2A2A2E.toInt()  // Skip button

private const val PATH_COMPLETE = "/neuroflow/complete"
private const val PATH_SNOOZE   = "/neuroflow/snooze"

class NeuroFlowTile : TileService() {

    private val scope = CoroutineScope(Dispatchers.IO)

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest
    ): ListenableFuture<TileBuilders.Tile> {
        val state = WearStateStore.current
        return Futures.immediateFuture(buildTile(state))
    }

    override fun onResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest
    ): ListenableFuture<ResourceBuilders.Resources> {
        return Futures.immediateFuture(
            ResourceBuilders.Resources.Builder()
                .setVersion("1")
                .build()
        )
    }

    // ------------------------------------------------------------------
    // Tile layout
    // ------------------------------------------------------------------

    private fun buildTile(state: WearState): TileBuilders.Tile {
        val layout = when {
            state.isEmpty || state.isStale -> buildOfflineLayout()
            !state.hasPrimaryTask          -> buildClearLayout()
            else                           -> buildTaskLayout(state)
        }

        return TileBuilders.Tile.Builder()
            .setResourcesVersion("1")
            .setTimeline(
                TimelineBuilders.Timeline.Builder()
                    .addTimelineEntry(
                        TimelineBuilders.TimelineEntry.Builder()
                            .setLayout(
                                Layout.Builder().setRoot(layout).build()
                            )
                            .build()
                    )
                    .build()
            )
            .build()
    }

    private fun buildTaskLayout(state: WearState): LayoutElement {
        return Column.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setHorizontalAlignment(HORIZONTAL_ALIGN_START)
            .addContent(
                // App name
                Text.Builder()
                    .setText("neuroflow")
                    .setFontStyle(
                        FontStyle.Builder()
                            .setSize(sp(11f))
                            .setColor(argb(COLOR_TEXT_MUTED))
                            .build()
                    )
                    .build()
            )
            .addContent(Spacer.Builder().setHeight(dp(8f)).build())
            .addContent(
                // Primary task title — 2-line max, large
                Text.Builder()
                    .setText(state.taskTitle)
                    .setMaxLines(2)
                    .setFontStyle(
                        FontStyle.Builder()
                            .setSize(sp(20f))
                            .setColor(argb(COLOR_TEXT_PRIMARY))
                            .setWeight(FONT_WEIGHT_BOLD)
                            .build()
                    )
                    .build()
            )
            .addContent(Spacer.Builder().setHeight(dp(16f)).build())
            .addContent(
                // Action row: Done | Skip
                Row.Builder()
                    .setWidth(expand())
                    .addContent(buildActionButton("✓ Done", COLOR_ACCENT, state.taskId, PATH_COMPLETE))
                    .addContent(Spacer.Builder().setWidth(dp(8f)).build())
                    .addContent(buildActionButton("Skip", COLOR_SURFACE, state.taskId, PATH_SNOOZE))
                    .build()
            )
            .build()
    }

    private fun buildClearLayout(): LayoutElement =
        Column.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(VERTICAL_ALIGN_CENTER)
            .addContent(
                Text.Builder()
                    .setText("You're clear.")
                    .setFontStyle(
                        FontStyle.Builder()
                            .setSize(sp(18f))
                            .setColor(argb(COLOR_TEXT_PRIMARY))
                            .build()
                    )
                    .build()
            )
            .addContent(
                Text.Builder()
                    .setText("Rest.")
                    .setFontStyle(
                        FontStyle.Builder()
                            .setSize(sp(14f))
                            .setColor(argb(COLOR_TEXT_MUTED))
                            .build()
                    )
                    .build()
            )
            .build()

    private fun buildOfflineLayout(): LayoutElement =
        Column.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setHorizontalAlignment(HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(VERTICAL_ALIGN_CENTER)
            .addContent(
                Text.Builder()
                    .setText("Open phone to refresh.")
                    .setMaxLines(2)
                    .setFontStyle(
                        FontStyle.Builder()
                            .setSize(sp(14f))
                            .setColor(argb(COLOR_TEXT_MUTED))
                            .build()
                    )
                    .build()
            )
            .build()

    private fun buildActionButton(
        label: String,
        bgColor: Int,
        taskId: String,
        messagePath: String,
    ): LayoutElement {
        // Tapping a tile button sends a local broadcast; we handle it in
        // WatchMessageSender (a BroadcastReceiver) which calls MessageClient.
        // Tile actions can't call suspend functions directly.
        val clickable = ActionBuilders.Clickable.Builder()
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(
                        AndroidActivity.Builder()
                            .setPackageName(packageName)
                            .setClassName("dev.neuroflow.WatchMessageSender")
                            .addKeyToExtraMapping("path", ActionBuilders.stringExtra(messagePath))
                            .addKeyToExtraMapping("taskId", ActionBuilders.stringExtra(taskId))
                            .build()
                    )
                    .build()
            )
            .build()

        return Box.Builder()
            .setBackground(
                Background.Builder()
                    .setColor(argb(bgColor))
                    .setCornerRadius(CornerRadius.Builder().setRadius(dp(8f)).build())
                    .build()
            )
            .setModifiers(
                Modifiers.Builder().setClickable(clickable).build()
            )
            .addContent(
                Text.Builder()
                    .setText(label)
                    .setFontStyle(
                        FontStyle.Builder()
                            .setSize(sp(14f))
                            .setColor(argb(COLOR_TEXT_PRIMARY))
                            .build()
                    )
                    .build()
            )
            .build()
    }
}
