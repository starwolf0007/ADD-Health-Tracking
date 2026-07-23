package com.neuroflow.healthconnect

import androidx.health.connect.client.HealthConnectClient
import org.junit.Assert.assertEquals
import org.junit.Test

class HealthConnectBridgeTest {
    private val bridge = HealthConnectBridge()

    @Test
    fun `maps available status`() {
        assertEquals(
            "available",
            bridge.mapSdkStatus(HealthConnectClient.SDK_AVAILABLE),
        )
    }

    @Test
    fun `maps provider update required status`() {
        assertEquals(
            "providerUpdateRequired",
            bridge.mapSdkStatus(
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED,
            ),
        )
    }

    @Test
    fun `maps sdk unavailable status`() {
        assertEquals(
            "sdkUnavailable",
            bridge.mapSdkStatus(HealthConnectClient.SDK_UNAVAILABLE),
        )
    }

    @Test
    fun `maps unknown status to unsupported`() {
        assertEquals(
            "unsupported",
            bridge.mapSdkStatus(Int.MIN_VALUE),
        )
    }

    @Test
    fun `maps only granted supported permissions to stable keys`() {
        val firstPermission = HealthConnectBridge.REQUIRED_PERMISSIONS.first()

        assertEquals(
            1,
            bridge.toWirePermissionKeys(setOf(firstPermission)).size,
        )
        assertEquals(
            emptyList<String>(),
            bridge.toWirePermissionKeys(setOf("future.permission")),
        )
    }
}
