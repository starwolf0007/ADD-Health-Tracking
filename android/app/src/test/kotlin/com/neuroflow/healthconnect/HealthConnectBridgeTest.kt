package com.neuroflow.healthconnect

import androidx.health.connect.client.HealthConnectClient
import org.junit.Assert.assertEquals
import org.junit.Test

class HealthConnectBridgeTest {
    private val bridge = HealthConnectBridge()

    @Test
    fun `maps available status`() {
        assertEquals(
            HealthConnectBridge.STATUS_AVAILABLE,
            bridge.mapSdkStatus(HealthConnectClient.SDK_AVAILABLE),
        )
    }

    @Test
    fun `maps provider update required status`() {
        assertEquals(
            HealthConnectBridge.STATUS_PROVIDER_UPDATE_REQUIRED,
            bridge.mapSdkStatus(
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED,
            ),
        )
    }

    @Test
    fun `maps sdk unavailable status`() {
        assertEquals(
            HealthConnectBridge.STATUS_SDK_UNAVAILABLE,
            bridge.mapSdkStatus(HealthConnectClient.SDK_UNAVAILABLE),
        )
    }

    @Test
    fun `maps unknown status to unsupported`() {
        assertEquals(
            HealthConnectBridge.STATUS_UNSUPPORTED,
            bridge.mapSdkStatus(Int.MIN_VALUE),
        )
    }

    @Test
    fun `maps only granted supported permissions to stable keys`() {
        assertEquals(
            listOf("steps"),
            bridge.toWirePermissionKeys(
                setOf(HealthConnectBridge.STEPS_READ_PERMISSION),
            ),
        )
        assertEquals(
            emptyList<String>(),
            bridge.toWirePermissionKeys(setOf("future.permission")),
        )
    }
}
