package io.github.xdaijobu.dozeless

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/** Hourly inexact alarm that repairs broken chains, replacing WorkManager. */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_WATCHDOG) check(context.applicationContext)
    }

    companion object {
        private const val ACTION_WATCHDOG = "io.github.xdaijobu.dozeless.WATCHDOG"

        /** Overdue jobs fire in one second with trigger=watchdog; vanished alarms are re-armed. */
        internal fun check(app: Context) {
            val store = JobStore(app)
            val scheduler = AlarmScheduler(app)
            val now = System.currentTimeMillis()
            for (job in store.all()) {
                if (job.state.mode == Mode.STOPPED) continue
                val id = job.spec.id
                val d = SchedulePolicy.onWatchdog(job.state.nextRunAt, job.spec.everyMs, now, scheduler.isArmed(id))
                if (d is SchedulePolicy.Decision.ArmAt) {
                    scheduler.armAndRecord(store, id, d.at, d.trigger)
                    Log.w(TAG, "watchdog id=$id nextRunAt=${job.state.nextRunAt} -> ${d.trigger} at ${d.at}")
                }
            }
        }

        /** [force] re-arms even if the PendingIntent still exists; it can outlive a force stop that deleted the alarm. */
        internal fun ensureArmed(app: Context, force: Boolean = false) {
            if (!force && pendingIntent(app, PendingIntent.FLAG_NO_CREATE) != null) return
            app.getSystemService(AlarmManager::class.java).setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + AlarmManager.INTERVAL_HOUR,
                AlarmManager.INTERVAL_HOUR,
                pendingIntent(app, PendingIntent.FLAG_UPDATE_CURRENT)!!,
            )
            Log.i(TAG, "watchdog armed")
        }

        internal fun cancel(app: Context) {
            pendingIntent(app, PendingIntent.FLAG_NO_CREATE)?.let {
                app.getSystemService(AlarmManager::class.java).cancel(it)
                it.cancel()
            }
        }

        private fun pendingIntent(app: Context, flag: Int): PendingIntent? = PendingIntent.getBroadcast(
            app,
            0,
            Intent(app, WatchdogReceiver::class.java).setAction(ACTION_WATCHDOG),
            flag or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
