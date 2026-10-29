package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import java.util.TimeZone

/** Manifest receiver for boot, app update and clock changes (spec §3 SystemEventReceiver). Never opens UI. */
class SystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, ACTION_QUICKBOOT_POWERON -> BootHandler.handleIfNew(app, viaBroadcast = true)
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.i(TAG, "package replaced")
                WatchdogReceiver.ensureArmed(app)
                Reconciler.restartAll(app, Triggers.PACKAGE_REPLACED)
            }
            Intent.ACTION_TIME_CHANGED -> onTimeSet(app)
            Intent.ACTION_TIMEZONE_CHANGED -> onTimezoneChanged(app, intent.getStringExtra(EXTRA_TIME_ZONE))
        }
    }

    private fun onTimeSet(app: Context) {
        val store = JobStore(app)
        val nowWall = System.currentTimeMillis()
        val nowElapsed = SystemClock.elapsedRealtime()
        val jump = store.timeRef?.let { TimeJump.jumpMs(it.first, it.second, nowWall, nowElapsed) }
        val autoTime = Settings.Global.getInt(app.contentResolver, Settings.Global.AUTO_TIME, 1) == 1
        store.timeRef = nowWall to nowElapsed
        if (!TimeJump.isSignificant(jump, autoTime)) return
        EventStore(app).append("timeChanged", nowWall, mapOf("jumpMs" to jump, "autoTime" to autoTime))
        // RTC alarms follow the wall clock: after a jump back the next alarm would come far too late.
        val scheduler = AlarmScheduler(app)
        for (job in store.all()) {
            if (job.state.mode == Mode.STOPPED) continue
            scheduler.armAndRecord(store, job.spec.id, nowWall + SchedulePolicy.REARM_DELAY_MS, Triggers.TIME_CHANGED)
        }
        Log.i(TAG, "time changed jumpMs=$jump autoTime=$autoTime")
    }

    private fun onTimezoneChanged(app: Context, newZone: String?) {
        val store = JobStore(app)
        val to = newZone ?: TimeZone.getDefault().id
        val from = store.lastTimezone
        store.lastTimezone = to
        if (from == to) return
        EventStore(app).append("timezoneChanged", System.currentTimeMillis(), mapOf("from" to from, "to" to to))
    }

    private companion object {
        const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
        const val EXTRA_TIME_ZONE = "time-zone"
    }
}
