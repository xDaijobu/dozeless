package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class EventsTest {
    private fun log(vararg seqs: Long) = seqs.map { SystemEvent(it, "boot", it * 10, emptyMap()) }

    @Test
    fun appendNumbersEventsAfterTheLastSeq() {
        val (events, seq) = EventLogPolicy.append(log(1, 2), lastSeq = 2, type = "timeChanged", at = 99, data = mapOf("jumpMs" to -3_600_000L))
        assertEquals(3, seq)
        assertEquals(listOf(1L, 2L, 3L), events.map { it.seq })
    }

    @Test
    fun appendDropsTheOldestBeyondTheCap() {
        val full = (1L..EventLogPolicy.MAX_EVENTS).map { SystemEvent(it, "processExit", it, emptyMap()) }
        val (events, _) = EventLogPolicy.append(full, EventLogPolicy.MAX_EVENTS.toLong(), "boot", 0, emptyMap())
        assertEquals(EventLogPolicy.MAX_EVENTS, events.size)
        assertEquals(2L, events.first().seq)
    }

    @Test
    fun pendingIsEverythingAfterTheJobsCursor() =
        assertEquals(listOf(3L, 4L), EventLogPolicy.pending(log(2, 3, 4), ackedSeq = 2).map { it.seq })

    @Test
    fun aNewJobStartingAtLastSeqSeesNoOlderEvents() =
        assertEquals(emptyList(), EventLogPolicy.pending(log(1, 2, 3), ackedSeq = 3))

    @Test
    fun aSuccessfulRunAcknowledgesWhatItWasGiven() =
        assertEquals(7L, EventLogPolicy.nextAck(acked = 4, delivered = 7, succeeded = true))

    @Test
    fun aFailedRunAcknowledgesNothingSoEventsComeAgain() =
        assertEquals(4L, EventLogPolicy.nextAck(acked = 4, delivered = 7, succeeded = false))

    @Test
    fun pruneKeepsWhatTheSlowestJobHasNotSeen() =
        assertEquals(listOf(3L, 4L), EventLogPolicy.prune(log(1, 2, 3, 4), ackedSeqs = listOf(4L, 2L)).map { it.seq })

    @Test
    fun pruneWithoutJobsClearsTheLog() =
        assertEquals(emptyList(), EventLogPolicy.prune(log(1, 2), ackedSeqs = emptyList()))

    @Test
    fun codecRoundTripsDataIncludingNulls() {
        val events = listOf(
            SystemEvent(1, "timezoneChanged", 5, mapOf("from" to null, "to" to "Asia/Jakarta")),
            SystemEvent(2, "timeChanged", 6, mapOf("jumpMs" to -3_600_000L, "autoTime" to false)),
        )
        assertEquals(events, EventCodec.decodeAll(EventCodec.encodeAll(events)))
    }

    @Test
    fun noJumpWhenBothClocksMovedTogether() =
        assertEquals(0L, TimeJump.jumpMs(refWall = 1_000_000, refElapsed = 5_000, nowWall = 1_060_000, nowElapsed = 65_000))

    @Test
    fun clockSetBackOneHourIsANegativeJump() =
        assertEquals(-3_600_000L, TimeJump.jumpMs(refWall = 10_000_000, refElapsed = 5_000, nowWall = 6_460_000, nowElapsed = 65_000))

    @Test
    fun referenceFromAnEarlierBootGivesNoJump() =
        assertNull(TimeJump.jumpMs(refWall = 1_000_000, refElapsed = 900_000, nowWall = 2_000_000, nowElapsed = 10_000))

    @Test
    fun smallCorrectionsWithAutomaticTimeAreIgnored() {
        assertFalse(TimeJump.isSignificant(59_999, autoTime = true))
        assertTrue(TimeJump.isSignificant(-60_000, autoTime = true))
        assertFalse(TimeJump.isSignificant(null, autoTime = true))
    }

    @Test
    fun anyChangeWithAutomaticTimeOffIsSignificant() =
        assertTrue(TimeJump.isSignificant(1_000, autoTime = false))

    @Test
    fun exitReasonNames() {
        assertEquals("USER_REQUESTED", ExitReasons.name(10))
        assertEquals("LOW_MEMORY", ExitReasons.name(3))
        assertEquals("REASON_99", ExitReasons.name(99))
    }
}
