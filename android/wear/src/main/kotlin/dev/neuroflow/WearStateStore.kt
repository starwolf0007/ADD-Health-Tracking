// wear/src/main/kotlin/dev/neuroflow/WearStateStore.kt
//
// In-memory store for the latest state pushed from the phone.
// Thread-safe singleton — accessed by WearDataReceiver, NeuroFlowTile,
// and NeuroFlowComplication.
//
// If the watch process is killed and restarted, the store resets to empty.
// The tile handles the empty state by showing "Open phone to refresh."
// The phone pushes a fresh DataItem on its next TodayState change.

package dev.neuroflow

import java.util.concurrent.atomic.AtomicReference

data class WearState(
    val taskId: String = "",
    val taskTitle: String = "",
    val quickWinCount: Int = 0,
    val pendingCount: Int = 0,
    val hasPrimaryTask: Boolean = false,
    val pushedAt: Long = 0L,
) {
    val isEmpty: Boolean get() = taskId.isEmpty()
    val isStale: Boolean get() =
        pushedAt > 0L && System.currentTimeMillis() - pushedAt > 30 * 60 * 1000L
}

object WearStateStore {
    private val _state = AtomicReference(WearState())

    val current: WearState get() = _state.get()

    fun update(
        taskId: String,
        taskTitle: String,
        quickWinCount: Int,
        pendingCount: Int,
        hasPrimaryTask: Boolean,
        pushedAt: Long,
    ) {
        _state.set(
            WearState(
                taskId        = taskId,
                taskTitle     = taskTitle,
                quickWinCount = quickWinCount,
                pendingCount  = pendingCount,
                hasPrimaryTask = hasPrimaryTask,
                pushedAt      = pushedAt,
            )
        )
    }
}
