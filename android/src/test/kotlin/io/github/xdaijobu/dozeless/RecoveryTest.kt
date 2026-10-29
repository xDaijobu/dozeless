package io.github.xdaijobu.dozeless

import io.github.xdaijobu.dozeless.ReconcilePolicy.Action
import kotlin.test.Test
import kotlin.test.assertEquals

internal class RecoveryTest {
    @Test
    fun firstStartEverIsNotABoot() =
        assertEquals(BootKind.FIRST_SEEN, BootDedupe.classify(null, BootInfo(3, 1_000_000)))

    @Test
    fun bootCompletedAndQuickbootOnTheSameBootAreHandledOnce() =
        assertEquals(BootKind.SAME_BOOT, BootDedupe.classify(BootInfo(3, 1_000_000), BootInfo(3, 1_000_020)))

    @Test
    fun changingTheClockIsNotANewBootWhenBootCountIsKnown() =
        assertEquals(BootKind.SAME_BOOT, BootDedupe.classify(BootInfo(3, 1_000_000), BootInfo(3, 1_000_000 - 3_600_000)))

    @Test
    fun higherBootCountIsANewBoot() =
        assertEquals(BootKind.NEW_BOOT, BootDedupe.classify(BootInfo(3, 1_000_000), BootInfo(4, 1_000_500)))

    @Test
    fun withoutBootCountBootTimeWithinAMinuteIsTheSameBoot() {
        assertEquals(BootKind.SAME_BOOT, BootDedupe.classify(BootInfo(null, 1_000_000), BootInfo(null, 1_059_999)))
        assertEquals(BootKind.NEW_BOOT, BootDedupe.classify(BootInfo(null, 1_000_000), BootInfo(null, 1_060_000)))
    }

    @Test
    fun shutdownMarkerWinsOverLastJob() =
        assertEquals(900L to "marker", ShutdownGuess.of(markerAt = 900, lastAliveAt = 800, bootTime = 1_000))

    @Test
    fun withoutMarkerTheLastJobIsTheBestGuess() =
        assertEquals(800L to "lastJob", ShutdownGuess.of(markerAt = null, lastAliveAt = 800, bootTime = 1_000))

    @Test
    fun markerFromAfterTheBootIsIgnored() =
        assertEquals(800L to "lastJob", ShutdownGuess.of(markerAt = 1_200, lastAliveAt = 800, bootTime = 1_000))

    @Test
    fun nothingKnownGivesUnknown() =
        assertEquals(null to "unknown", ShutdownGuess.of(markerAt = null, lastAliveAt = null, bootTime = 1_000))

    // A force stop deletes the alarms but on Android 14 not the PendingIntents, so "armed" cannot be trusted.
    @Test
    fun reconcileAlwaysRearmsEveryActiveJob() {
        assertEquals(Action.REARM, ReconcilePolicy.decide(Mode.EXACT, emptyList()))
        assertEquals(Action.REARM, ReconcilePolicy.decide(Mode.INEXACT, emptyList()))
    }

    @Test
    fun reconcileStopsAJobWhosePrerequisiteWentMissing() =
        assertEquals(Action.STOP, ReconcilePolicy.decide(Mode.INEXACT, listOf(Prereq.NOT_BACKGROUND_RESTRICTED)))

    @Test
    fun reconcileResumesAStoppedJobOnlyWhenNothingIsMissing() {
        assertEquals(Action.RESUME, ReconcilePolicy.decide(Mode.STOPPED, emptyList()))
        assertEquals(Action.NONE, ReconcilePolicy.decide(Mode.STOPPED, listOf(Prereq.LOCATION)))
    }
}
