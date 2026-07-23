package com.neuroflow.healthconnect

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant

/** Reads one complete bounded Steps window. Partial pages are never returned. */
internal class HealthConnectStepsReader(
    private val client: HealthConnectClient,
) {
    suspend fun readAll(
        startInclusive: Instant,
        endExclusive: Instant,
    ): List<Map<String, Any?>> {
        val records = mutableListOf<Map<String, Any?>>()
        var pageToken: String? = null

        do {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(
                        startTime = startInclusive,
                        endTime = endExclusive,
                    ),
                    pageToken = pageToken,
                ),
            )
            records += response.records.map(HealthConnectRecordMapper::stepsToWire)
            pageToken = response.pageToken
        } while (pageToken != null)

        return records
    }
}
