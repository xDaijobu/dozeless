package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.SystemClock
import android.provider.Settings
import kotlin.math.abs

internal data class BootInfo(val bootCount: Int?, val bootTime: Long) {
    fun isFirstRunSinceBoot(lastRunAt: Long?): Boolean = lastRunAt == null || lastRunAt < bootTime

    companion object {
        fun read(context: Context) = BootInfo(
            bootCount = try {
                Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
            } catch (e: Settings.SettingNotFoundException) {
                null
            },
            bootTime = System.currentTimeMillis() - SystemClock.elapsedRealtime(),
        )
    }
}

internal enum class BootKind { FIRST_SEEN, SAME_BOOT, NEW_BOOT }

internal object BootDedupe {
    /** bootTime comes from two clocks and jitters, and moves when the user changes the clock. */
    private const val TOLERANCE_MS = 60_000L

    fun classify(handled: BootInfo?, current: BootInfo): BootKind = when {
        handled == null -> BootKind.FIRST_SEEN
        handled.bootCount != null && current.bootCount != null ->
            if (handled.bootCount == current.bootCount) BootKind.SAME_BOOT else BootKind.NEW_BOOT
        abs(handled.bootTime - current.bootTime) < TOLERANCE_MS -> BootKind.SAME_BOOT
        else -> BootKind.NEW_BOOT
    }
}

internal object ShutdownGuess {
    /** Best guess of when the phone went down before the boot at [bootTime]. */
    fun of(markerAt: Long?, lastAliveAt: Long?, bootTime: Long): Pair<Long?, String> = when {
        markerAt != null && markerAt <= bootTime -> markerAt to "marker"
        lastAliveAt != null && lastAliveAt <= bootTime -> lastAliveAt to "lastJob"
        else -> null to "unknown"
    }
}
