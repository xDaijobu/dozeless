package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class SnapshotTest {
    private val allOk = PrereqSnapshot(
        location = true, backgroundLocation = true, batteryUnrestricted = true, backgroundRestricted = false,
        exactAlarm = true, notification = true, autostartSettingAvailable = false,
    )

    @Test
    fun nothingMissingWhenEverythingIsGranted() =
        assertEquals(emptyList(), allOk.missing(setOf(Prereq.LOCATION) + Prereq.ALWAYS))

    @Test
    fun missingListsOnlyRequiredOnesInEnumOrder() {
        val s = allOk.copy(location = false, backgroundLocation = false, backgroundRestricted = true)
        assertEquals(listOf(Prereq.BACKGROUND_LOCATION, Prereq.NOT_BACKGROUND_RESTRICTED), s.missing(setOf(Prereq.NOT_BACKGROUND_RESTRICTED, Prereq.BACKGROUND_LOCATION)))
    }

    @Test
    fun everyJobImplicitlyNeedsBatteryAndNoBackgroundRestriction() {
        val spec = JobSpec("send", 1L, 60_000, 45_000, requires = emptySet())
        val s = allOk.copy(batteryUnrestricted = false)
        assertEquals(listOf(Prereq.BATTERY_UNRESTRICTED), s.missing(spec.effectiveRequires))
    }

    @Test
    fun exactAlarmAndNotificationNeverBlock() =
        assertEquals(emptyList(), allOk.copy(exactAlarm = false, notification = false).missing(Prereq.entries.toSet()))

    @Test
    fun autostartPagesExistOnlyForKnownBrands() {
        assertEquals(1, AutostartIntents.candidates("Xiaomi").size)
        assertEquals(3, AutostartIntents.candidates("realme").size)
        assertTrue(AutostartIntents.candidates("samsung").isEmpty())
    }

    @Test
    fun standbyBucketNames() {
        assertEquals("active", StandbyBuckets.name(10))
        assertEquals("rare", StandbyBuckets.name(40))
        assertEquals("restricted", StandbyBuckets.name(45))
        assertEquals("unknown", StandbyBuckets.name(99))
    }

    @Test
    fun firstRunSinceBootComparesLastRunWithBootTime() {
        val boot = BootInfo(bootCount = 12, bootTime = 1_000)
        assertTrue(boot.isFirstRunSinceBoot(null))
        assertTrue(boot.isFirstRunSinceBoot(999))
        assertFalse(boot.isFirstRunSinceBoot(1_001))
    }
}
