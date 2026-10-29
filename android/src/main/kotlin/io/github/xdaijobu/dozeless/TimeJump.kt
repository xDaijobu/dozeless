package io.github.xdaijobu.dozeless

import kotlin.math.abs

internal object TimeJump {
    const val SIGNIFICANT_MS = 60_000L

    /** How far the wall clock moved relative to elapsedRealtime, or null if the reference is from an earlier boot. */
    fun jumpMs(refWall: Long, refElapsed: Long, nowWall: Long, nowElapsed: Long): Long? =
        if (nowElapsed < refElapsed) null else (nowWall - refWall) - (nowElapsed - refElapsed)

    /** Spec §6 TIME_CHANGED: a jump of at least 60 s, or any change while automatic time is off. */
    fun isSignificant(jumpMs: Long?, autoTime: Boolean): Boolean =
        !autoTime || (jumpMs != null && abs(jumpMs) >= SIGNIFICANT_MS)
}
