package com.neuroflow.healthconnect

import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Metadata

/** Maps Health Connect SDK records to the frozen primitive transport contract. */
internal object HealthConnectRecordMapper {
    fun stepsToWire(record: StepsRecord): Map<String, Any?> = mapOf(
        "externalId" to record.metadata.id,
        "recordType" to "steps",
        "count" to record.count,
        "startEpochMs" to record.startTime.toEpochMilli(),
        "endEpochMs" to record.endTime.toEpochMilli(),
        "startZoneOffsetSeconds" to record.startZoneOffset?.totalSeconds,
        "endZoneOffsetSeconds" to record.endZoneOffset?.totalSeconds,
        "sourceAppId" to record.metadata.dataOrigin.packageName,
        "lastModifiedEpochMs" to record.metadata.lastModifiedTime.toEpochMilli(),
        "clientRecordId" to record.metadata.clientRecordId,
        "clientRecordVersion" to record.metadata.clientRecordVersion,
        "recordingMethod" to recordingMethodToWire(record.metadata.recordingMethod),
    )

    fun recordingMethodToWire(recordingMethod: Int): String = when (recordingMethod) {
        Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED -> "automatic"
        Metadata.RECORDING_METHOD_ACTIVELY_RECORDED -> "active"
        Metadata.RECORDING_METHOD_MANUAL_ENTRY -> "manual"
        Metadata.RECORDING_METHOD_UNKNOWN -> "unknown"
        else -> "unknown"
    }
}
