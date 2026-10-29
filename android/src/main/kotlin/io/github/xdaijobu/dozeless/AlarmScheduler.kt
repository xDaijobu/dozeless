package io.github.xdaijobu.dozeless

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log

/** One-shot exact alarm per job id, with an inexact fallback (spec §3 AlarmScheduler). */
internal class AlarmScheduler(private val context: Context) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    /** Arms [id] at [at] (wall clock) and returns the mode actually used. */
    fun arm(id: String, at: Long, trigger: String = Triggers.ALARM): Mode {
        val pi = pendingIntent(id, at, trigger, PendingIntent.FLAG_UPDATE_CURRENT)!!
        if (canExact()) {
            try {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                return Mode.EXACT
            } catch (e: SecurityException) {
                Log.w(TAG, "exact alarm denied for $id, falling back to inexact", e)
            }
        }
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        return Mode.INEXACT
    }

    /** [arm] and remember the planned time and the mode on the stored job. */
    fun armAndRecord(store: JobStore, id: String, at: Long, trigger: String = Triggers.ALARM): Mode =
        arm(id, at, trigger).also { mode -> store.update(id) { it.copy(nextRunAt = at, mode = mode) } }

    fun cancel(id: String) {
        pendingIntent(id, 0, Triggers.ALARM, PendingIntent.FLAG_NO_CREATE)?.let {
            alarmManager.cancel(it)
            it.cancel()
        }
    }

    /** Only a hint: the PendingIntent survives process death and, on Android 14, even a force stop that deleted the alarm. */
    fun isArmed(id: String): Boolean = pendingIntent(id, 0, Triggers.ALARM, PendingIntent.FLAG_NO_CREATE) != null

    fun canExact(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) alarmManager.canScheduleExactAlarms() else true

    // Extras do not take part in PendingIntent identity, so FLAG_NO_CREATE finds the alarm whatever its trigger.
    private fun pendingIntent(id: String, at: Long, trigger: String, flag: Int): PendingIntent? {
        val intent = Intent(context, JobReceiver::class.java)
            .setAction(JobReceiver.ACTION_RUN)
            .setData(Uri.parse("dozeless://job/" + Uri.encode(id)))
            .putExtra(JobReceiver.EXTRA_JOB_ID, id)
            .putExtra(JobReceiver.EXTRA_SCHEDULED_AT, at)
            .putExtra(JobReceiver.EXTRA_TRIGGER, trigger)
        return PendingIntent.getBroadcast(context, 0, intent, flag or PendingIntent.FLAG_IMMUTABLE)
    }
}
