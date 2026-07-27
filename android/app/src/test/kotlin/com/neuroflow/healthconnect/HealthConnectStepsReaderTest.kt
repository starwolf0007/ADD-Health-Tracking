package com.neuroflow.healthconnect

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.aggregate.AggregationResultGroupedByDuration
import androidx.health.connect.client.aggregate.AggregationResultGroupedByPeriod
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByDurationRequest
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ChangesResponse
import androidx.health.connect.client.response.InsertRecordsResponse
import androidx.health.connect.client.response.ReadRecordResponse
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import kotlin.reflect.KClass
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class HealthConnectStepsReaderTest {

    private val start = Instant.parse("2026-07-01T00:00:00Z")
    private val end = Instant.parse("2026-07-02T00:00:00Z")

    @Test
    fun `returns all records from a single page when pageToken is null`() = runBlocking {
        val client = FakeHealthConnectClient(
            listOf(ReadRecordsResponse(listOf(stepsRecord("a", 100), stepsRecord("b", 200)), null)),
        )

        val result = HealthConnectStepsReader(client).readAll(start, end)

        assertEquals(listOf("a", "b"), result.map { it["externalId"] })
        assertEquals(1, client.requests.size)
    }

    @Test
    fun `gathers every page without duplication or truncation`() = runBlocking {
        val client = FakeHealthConnectClient(
            listOf(
                ReadRecordsResponse(listOf(stepsRecord("a", 100)), "token-1"),
                ReadRecordsResponse(listOf(stepsRecord("b", 200)), "token-2"),
                ReadRecordsResponse(listOf(stepsRecord("c", 300)), null),
            ),
        )

        val result = HealthConnectStepsReader(client).readAll(start, end)

        assertEquals(listOf("a", "b", "c"), result.map { it["externalId"] })
        assertEquals(3, client.requests.size)
        assertEquals(null, client.requests[0].pageToken)
        assertEquals("token-1", client.requests[1].pageToken)
        assertEquals("token-2", client.requests[2].pageToken)
    }

    @Test
    fun `returns an empty list for a successful empty read`() = runBlocking {
        val client = FakeHealthConnectClient(listOf(ReadRecordsResponse(emptyList(), null)))

        val result = HealthConnectStepsReader(client).readAll(start, end)

        assertTrue(result.isEmpty())
        assertEquals(1, client.requests.size)
    }

    @Test
    fun `requests the same bounded time range on every page`() = runBlocking {
        val client = FakeHealthConnectClient(
            listOf(
                ReadRecordsResponse(listOf(stepsRecord("a", 1)), "token-1"),
                ReadRecordsResponse(listOf(stepsRecord("b", 2)), null),
            ),
        )

        HealthConnectStepsReader(client).readAll(start, end)

        val expected = TimeRangeFilter.between(start, end)
        client.requests.forEach { assertEquals(expected, it.timeRangeFilter) }
    }

    @Test
    fun `propagates a SecurityException instead of swallowing it`(): Unit = runBlocking {
        val client = FakeHealthConnectClient(throwingImmediately = SecurityException("no permission"))

        try {
            HealthConnectStepsReader(client).readAll(start, end)
            fail("expected SecurityException to propagate")
        } catch (expected: SecurityException) {
            // Classification into the closed-envelope status is the caller's job
            // (HealthConnectBridge.readSteps), not the reader's — it must not swallow this.
        }
    }

    @Test
    fun `propagates CancellationException instead of swallowing it`(): Unit = runBlocking {
        val client = FakeHealthConnectClient(throwingImmediately = CancellationException("cancelled"))

        try {
            HealthConnectStepsReader(client).readAll(start, end)
            fail("expected CancellationException to propagate")
        } catch (expected: CancellationException) {
            // Coroutine cancellation must never be caught-and-suppressed here.
        }
    }

    @Test
    fun `stops paging and propagates a failure raised mid-sequence`(): Unit = runBlocking {
        val client = FakeHealthConnectClient(
            responses = listOf(ReadRecordsResponse(listOf(stepsRecord("a", 1)), "token-1")),
            throwingAfterResponses = RuntimeException("boom"),
        )

        try {
            HealthConnectStepsReader(client).readAll(start, end)
            fail("expected the second page's failure to propagate")
        } catch (expected: RuntimeException) {
            assertEquals("boom", expected.message)
        }
        assertEquals(2, client.requests.size)
    }

    private fun stepsRecord(id: String, count: Long): StepsRecord = StepsRecord(
        startTime = start,
        startZoneOffset = null,
        endTime = end,
        endZoneOffset = null,
        count = count,
        metadata = Metadata.manualEntryWithId(id),
    )
}

/**
 * Hand-rolled HealthConnectClient fake. HealthConnectStepsReader only ever calls readRecords,
 * so every other interface member fails loudly if a test path accidentally reaches it — avoids
 * pulling in a mocking library for a single suspend function.
 */
private class FakeHealthConnectClient(
    private val responses: List<ReadRecordsResponse<StepsRecord>> = emptyList(),
    private val throwingImmediately: Throwable? = null,
    private val throwingAfterResponses: Throwable? = null,
) : HealthConnectClient {

    val requests = mutableListOf<ReadRecordsRequest<*>>()
    private var callIndex = 0

    override val permissionController: PermissionController
        get() = error("not used by HealthConnectStepsReader")

    @Suppress("UNCHECKED_CAST")
    override suspend fun <T : Record> readRecords(
        request: ReadRecordsRequest<T>,
    ): ReadRecordsResponse<T> {
        requests += request
        throwingImmediately?.let { throw it }
        if (callIndex >= responses.size) {
            throwingAfterResponses?.let { throw it }
            error("unexpected extra readRecords call #${callIndex + 1}")
        }
        return responses[callIndex++] as ReadRecordsResponse<T>
    }

    override suspend fun insertRecords(records: List<Record>): InsertRecordsResponse =
        error("not used")

    override suspend fun updateRecords(records: List<Record>) = error("not used")

    override suspend fun deleteRecords(
        recordType: KClass<out Record>,
        recordIdsList: List<String>,
        clientRecordIdsList: List<String>,
    ) = error("not used")

    override suspend fun deleteRecords(
        recordType: KClass<out Record>,
        timeRangeFilter: TimeRangeFilter,
    ) = error("not used")

    override suspend fun <T : Record> readRecord(
        recordType: KClass<T>,
        recordId: String,
    ): ReadRecordResponse<T> = error("not used")

    override suspend fun aggregate(request: AggregateRequest): AggregationResult =
        error("not used")

    override suspend fun aggregateGroupByDuration(
        request: AggregateGroupByDurationRequest,
    ): List<AggregationResultGroupedByDuration> = error("not used")

    override suspend fun aggregateGroupByPeriod(
        request: AggregateGroupByPeriodRequest,
    ): List<AggregationResultGroupedByPeriod> = error("not used")

    override suspend fun getChangesToken(request: ChangesTokenRequest): String = error("not used")

    override suspend fun getChanges(changesToken: String): ChangesResponse = error("not used")
}
