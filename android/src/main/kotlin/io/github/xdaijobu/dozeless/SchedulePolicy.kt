package io.github.xdaijobu.dozeless

/** Pure decisions about when a job's alarm should fire. */
internal object SchedulePolicy {
    /** How soon a vanished or overdue alarm is re-armed. */
    const val REARM_DELAY_MS = 1_000L

    sealed interface Decision {
        data object Keep : Decision
        data class ArmAt(val at: Long, val trigger: String = Triggers.ALARM) : Decision
    }

    /** schedule() runs on every app start, so it must never push an armed job's next run later. */
    fun onSchedule(existing: Job?, spec: JobSpec, now: Long, armed: Boolean): Decision = when {
        existing == null -> Decision.ArmAt(now + spec.everyMs)
        existing.state.mode == Mode.STOPPED -> Decision.Keep
        existing.spec.copy(callbackHandle = spec.callbackHandle) != spec -> Decision.ArmAt(now + spec.everyMs)
        !armed -> Decision.ArmAt(rearmAt(existing.state.nextRunAt, now))
        else -> Decision.Keep
    }

    /** Hourly watchdog: overdue means the alarm is more than 2x the interval late. */
    fun onWatchdog(nextRunAt: Long?, everyMs: Long, now: Long, armed: Boolean): Decision = when {
        nextRunAt == null || now - nextRunAt > 2 * everyMs -> Decision.ArmAt(now + REARM_DELAY_MS, Triggers.WATCHDOG)
        !armed -> Decision.ArmAt(rearmAt(nextRunAt, now))
        else -> Decision.Keep
    }

    /** Never arm in the past: a missed time becomes "almost now". */
    fun rearmAt(nextRunAt: Long?, now: Long): Long =
        if (nextRunAt != null && nextRunAt > now) nextRunAt else now + REARM_DELAY_MS
}
