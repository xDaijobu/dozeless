package io.github.xdaijobu.dozeless

import io.github.xdaijobu.dozeless.SchedulePolicy.Decision.ArmAt
import io.github.xdaijobu.dozeless.SchedulePolicy.Decision.Keep
import io.github.xdaijobu.dozeless.SchedulePolicy.REARM_DELAY_MS
import kotlin.test.Test
import kotlin.test.assertEquals

internal class SchedulePolicyTest {
    private val now = 1_700_000_000_000L
    private val spec = JobSpec("get", callbackHandle = 1L, everyMs = 60_000, timeoutMs = 45_000, requires = emptySet())

    private fun job(state: JobState = JobState(nextRunAt = now + 30_000)) = Job(spec, state)

    @Test
    fun newJobArmsOneIntervalFromNow() =
        assertEquals(ArmAt(now + 60_000), SchedulePolicy.onSchedule(null, spec, now, armed = false))

    @Test
    fun sameSpecWhileArmedKeepsTheCurrentAlarm() =
        assertEquals(Keep, SchedulePolicy.onSchedule(job(), spec, now, armed = true))

    @Test
    fun newCallbackHandleAloneKeepsTheCurrentAlarm() =
        assertEquals(Keep, SchedulePolicy.onSchedule(job(), spec.copy(callbackHandle = 2L), now, armed = true))

    @Test
    fun changedIntervalRearmsFromNow() =
        assertEquals(ArmAt(now + 120_000), SchedulePolicy.onSchedule(job(), spec.copy(everyMs = 120_000), now, armed = true))

    @Test
    fun vanishedAlarmIsRearmedAtItsPlannedTime() =
        assertEquals(ArmAt(now + 30_000), SchedulePolicy.onSchedule(job(), spec, now, armed = false))

    @Test
    fun vanishedOverdueAlarmIsRearmedAlmostImmediately() =
        assertEquals(ArmAt(now + REARM_DELAY_MS), SchedulePolicy.onSchedule(job(JobState(nextRunAt = now - 600_000)), spec, now, armed = false))

    @Test
    fun stoppedJobIsLeftAlone() =
        assertEquals(Keep, SchedulePolicy.onSchedule(job(JobState(mode = Mode.STOPPED)), spec, now, armed = false))

    @Test
    fun watchdogKeepsAHealthyChain() =
        assertEquals(Keep, SchedulePolicy.onWatchdog(now + 30_000, 60_000, now, armed = true))

    @Test
    fun watchdogToleratesUpToTwoIntervalsLate() =
        assertEquals(Keep, SchedulePolicy.onWatchdog(now - 120_000, 60_000, now, armed = true))

    @Test
    fun watchdogRunsAJobMoreThanTwoIntervalsLate() =
        assertEquals(ArmAt(now + REARM_DELAY_MS, Triggers.WATCHDOG), SchedulePolicy.onWatchdog(now - 120_001, 60_000, now, armed = true))

    @Test
    fun watchdogRearmsAVanishedAlarmThatIsNotLateYet() =
        assertEquals(ArmAt(now + 30_000), SchedulePolicy.onWatchdog(now + 30_000, 60_000, now, armed = false))
}
