package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.SystemClock
import java.util.TimeZone

/** Cheap upkeep at the start of every job run. */
internal object Housekeeping {
    fun onJobStart(app: Context) {
        WatchdogReceiver.ensureArmed(app)
        val store = JobStore(app)
        store.timeRef = System.currentTimeMillis() to SystemClock.elapsedRealtime()
        if (store.lastTimezone == null) store.lastTimezone = TimeZone.getDefault().id
        ExitInfoReader.collect(app)
    }
}
