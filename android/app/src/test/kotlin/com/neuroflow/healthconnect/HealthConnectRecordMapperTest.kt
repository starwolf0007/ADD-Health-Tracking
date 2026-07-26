package com.neuroflow.healthconnect

import androidx.health.connect.client.records.metadata.Metadata
import org.junit.Assert.assertEquals
import org.junit.Test

class HealthConnectRecordMapperTest {
    @Test
    fun `maps named recording method constants to stable strings`() {
        assertEquals(
            "automatic",
            HealthConnectRecordMapper.recordingMethodToWire(
                Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED,
            ),
        )
        assertEquals(
            "active",
            HealthConnectRecordMapper.recordingMethodToWire(
                Metadata.RECORDING_METHOD_ACTIVELY_RECORDED,
            ),
        )
        assertEquals(
            "manual",
            HealthConnectRecordMapper.recordingMethodToWire(
                Metadata.RECORDING_METHOD_MANUAL_ENTRY,
            ),
        )
        assertEquals(
            "unknown",
            HealthConnectRecordMapper.recordingMethodToWire(
                Metadata.RECORDING_METHOD_UNKNOWN,
            ),
        )
    }

    @Test
    fun `future recording method constants fail closed`() {
        assertEquals(
            "unknown",
            HealthConnectRecordMapper.recordingMethodToWire(Int.MAX_VALUE),
        )
    }
}
