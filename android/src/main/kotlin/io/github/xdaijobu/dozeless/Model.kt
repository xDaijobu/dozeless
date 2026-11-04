package io.github.xdaijobu.dozeless

/** Log tag of every native message: `adb logcat -s Dozeless`. */
internal const val TAG = "Dozeless"

/** Why a run started. Values equal the Dart `JobTrigger` names. */
internal object Triggers {
    const val ALARM = "alarm"
    const val BOOT = "boot"
    const val WATCHDOG = "watchdog"
    const val PACKAGE_REPLACED = "packageReplaced"
    const val TIME_CHANGED = "timeChanged"
    const val PREREQUISITE_LOST = "prerequisiteLost"
    const val RESUMED = "resumed"
    const val MANUAL = "manual"
}

internal enum class Mode(val wire: String) {
    EXACT("exact"),
    INEXACT("inexact"),
    STOPPED("stopped");

    companion object {
        fun fromWire(value: String?): Mode = entries.firstOrNull { it.wire == value } ?: EXACT
    }
}

internal enum class Prereq(val wire: String) {
    LOCATION("location"),
    BACKGROUND_LOCATION("backgroundLocation"),
    BATTERY_UNRESTRICTED("batteryUnrestricted"),
    NOT_BACKGROUND_RESTRICTED("notBackgroundRestricted");

    companion object {
        fun fromWire(value: String): Prereq? = entries.firstOrNull { it.wire == value }

        /** Without these no alarm runs in the background, so every job needs them. */
        val ALWAYS: Set<Prereq> = setOf(BATTERY_UNRESTRICTED, NOT_BACKGROUND_RESTRICTED)
    }
}

internal data class JobSpec(
    val id: String,
    val callbackHandle: Long,
    val everyMs: Long,
    val timeoutMs: Long,
    val requires: Set<Prereq>,
) {
    val effectiveRequires: Set<Prereq> get() = requires + Prereq.ALWAYS
}

internal data class JobState(
    val mode: Mode = Mode.EXACT,
    val nextRunAt: Long? = null,
    val lastRunAt: Long? = null,
    val lastFinishedAt: Long? = null,
    val lastDurationMs: Long? = null,
    val lastError: String? = null,
    val lastTrigger: String? = null,
    val runCount: Long = 0,
    val skippedBusyCount: Long = 0,
    val ackedEventSeq: Long = 0,
    val missing: List<Prereq> = emptyList(),
    val stoppedAt: Long? = null,
)

internal data class Job(val spec: JobSpec, val state: JobState)
