package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Receives job alarms and immediate dispatches, then hands over to [JobRunner]. */
class JobReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RUN) return
        val id = intent.getStringExtra(EXTRA_JOB_ID) ?: return
        val trigger = intent.getStringExtra(EXTRA_TRIGGER) ?: Triggers.ALARM
        val firedAt = System.currentTimeMillis()
        val scheduledAt = intent.getLongExtra(EXTRA_SCHEDULED_AT, firedAt)
        val pending = goAsync()
        JobRunner.run(context.applicationContext, id, trigger, scheduledAt, firedAt) { pending.finish() }
    }

    companion object {
        const val ACTION_RUN = "io.github.xdaijobu.dozeless.RUN"
        const val EXTRA_JOB_ID = "jobId"
        const val EXTRA_TRIGGER = "trigger"
        const val EXTRA_SCHEDULED_AT = "scheduledAt"

        /** Runs [id] now through the same path as an alarm. Only for moments the device is awake. */
        fun dispatch(context: Context, id: String, trigger: String) {
            context.sendBroadcast(
                Intent(context, JobReceiver::class.java)
                    .setAction(ACTION_RUN)
                    .putExtra(EXTRA_JOB_ID, id)
                    .putExtra(EXTRA_TRIGGER, trigger)
                    .putExtra(EXTRA_SCHEDULED_AT, System.currentTimeMillis()),
            )
        }
    }
}
