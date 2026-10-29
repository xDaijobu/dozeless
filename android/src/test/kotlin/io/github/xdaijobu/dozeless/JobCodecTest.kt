package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class JobCodecTest {
    // Larger than 2^53: proves 64-bit callback handles survive JSON.
    private val spec = JobSpec(
        id = "get",
        callbackHandle = 9_007_199_254_740_993L,
        everyMs = 300_000,
        timeoutMs = 45_000,
        requires = setOf(Prereq.LOCATION, Prereq.BACKGROUND_LOCATION),
    )

    @Test
    fun roundTripsAFullJob() {
        val job = Job(
            spec,
            JobState(
                mode = Mode.STOPPED, nextRunAt = 1L, lastRunAt = 2L, lastFinishedAt = 3L, lastDurationMs = 4L,
                lastError = "JOB_TIMEOUT", lastTrigger = Triggers.WATCHDOG, runCount = 5, skippedBusyCount = 6,
                ackedEventSeq = 7, missing = listOf(Prereq.BACKGROUND_LOCATION), stoppedAt = 8L,
            ),
        )
        assertEquals(job, JobCodec.decode(JobCodec.encode(job)))
    }

    @Test
    fun roundTripsAFreshJobWithNulls() {
        val job = Job(spec, JobState())
        assertEquals(job, JobCodec.decode(JobCodec.encode(job)))
    }

    @Test
    fun ignoresUnknownPrerequisiteNames() {
        val json = JobCodec.encode(Job(spec, JobState())).replace("\"location\"", "\"teleport\"")
        assertEquals(setOf(Prereq.BACKGROUND_LOCATION), JobCodec.decode(json).spec.requires)
    }

    @Test
    fun statusMapUsesWireNames() {
        val map = JobCodec.statusMap(Job(spec, JobState(mode = Mode.INEXACT, missing = listOf(Prereq.BATTERY_UNRESTRICTED))))
        assertEquals("inexact", map["mode"])
        assertEquals(listOf("batteryUnrestricted"), map["missing"])
        assertNull(map["lastError"])
    }
}
