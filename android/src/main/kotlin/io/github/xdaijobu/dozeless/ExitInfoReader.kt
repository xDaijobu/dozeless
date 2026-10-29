package io.github.xdaijobu.dozeless

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.util.Log

internal object ExitReasons {
    /** ApplicationExitInfo.REASON_* codes; spelled out so the names survive older compile SDKs. */
    fun name(code: Int): String = when (code) {
        0 -> "UNKNOWN"
        1 -> "EXIT_SELF"
        2 -> "SIGNALED"
        3 -> "LOW_MEMORY"
        4 -> "CRASH"
        5 -> "CRASH_NATIVE"
        6 -> "ANR"
        7 -> "INITIALIZATION_FAILURE"
        8 -> "PERMISSION_CHANGE"
        9 -> "EXCESSIVE_RESOURCE_USAGE"
        10 -> "USER_REQUESTED"
        11 -> "USER_STOPPED"
        12 -> "DEPENDENCY_DIED"
        13 -> "OTHER"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED"
        else -> "REASON_$code"
    }
}

/** Turns new getHistoricalProcessExitReasons entries (Android 11+) into `processExit` events. */
internal object ExitInfoReader {
    fun collect(app: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val store = JobStore(app)
        val infos = try {
            app.getSystemService(ActivityManager::class.java).getHistoricalProcessExitReasons(app.packageName, 0, 0)
        } catch (e: Exception) {
            Log.w(TAG, "exit reasons unavailable", e)
            return
        }
        val since = store.lastExitReadAt
        if (since == null) {
            // First read ever: history from before this plugin was installed is not ours to report.
            store.lastExitReadAt = infos.maxOfOrNull { it.timestamp } ?: System.currentTimeMillis()
            return
        }
        val fresh = infos.filter { it.timestamp > since }.sortedBy { it.timestamp }
        if (fresh.isEmpty()) return
        val events = EventStore(app)
        for (info in fresh) {
            events.append(
                "processExit",
                info.timestamp,
                mapOf(
                    "reason" to ExitReasons.name(info.reason),
                    "reasonCode" to info.reason.toLong(),
                    "importance" to info.importance.toLong(),
                    "description" to info.description,
                ),
            )
        }
        store.lastExitReadAt = fresh.last().timestamp
    }
}
