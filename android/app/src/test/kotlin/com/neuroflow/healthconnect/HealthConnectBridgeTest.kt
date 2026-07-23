package com.neuroflow.healthconnect

import androidx.health.connect.client.HealthConnectClient
import org.junit.Assert.assertEquals
import org.junit.Test

class HealthConnectBridgeTest {
    @Test
    fun `maps available status`() {
        assertEquals(
            HealthConnectBridge.STATUS_AVAILABLE,
            HealthConnectBridge.mapSdkStatus(HealthConnectClient.SDK_AVAILABLE),
        )
    }

    @Test
    fun `maps provider update required status`() {
        assertEquals(
            HealthConnectBridge.STATUS_PROVIDER_UPDATE_REQUIRED,
            HealthConnectBridge.mapSdkStatus(
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED,
            ),
        )
    }

    @Test
    fun `maps sdk unavailable status`() {
        assertEquals(
            HealthConnectBridge.STATUS_SDK_UNAVAILABLE,
            HealthConnectBridge.mapSdkStatus(HealthConnectClient.SDK_UNAVAILABLE),
        )
    }

    @Test
    fun `maps unknown status to unsupported`() {
        assertEquals(
            HealthConnectBridge.STATUS_UNSUPPORTED,
            HealthConnectBridge.mapSdkStatus(Int.MIN_VALUE),
        )
    }
}
