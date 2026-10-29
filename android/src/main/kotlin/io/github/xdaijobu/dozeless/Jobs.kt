package io.github.xdaijobu.dozeless

import android.content.Context
import android.util.Log

/** Job operations called from the Dart API. */
internal object Jobs {
    fun schedule(app: Context, spec: JobSpec) {
        val store = JobStore(app)
        val scheduler = AlarmScheduler(app)
        val existing = store.get(spec.id)
        // A new job starts after the newest event, so it never receives events from before it existed.
        val state = existing?.state ?: JobState(ackedEventSeq = EventStore(app).lastSeq)
        when (val d = SchedulePolicy.onSchedule(existing, spec, System.currentTimeMillis(), scheduler.isArmed(spec.id))) {
            SchedulePolicy.Decision.Keep -> store.put(Job(spec, state))
            is SchedulePolicy.Decision.ArmAt -> {
                val mode = scheduler.arm(spec.id, d.at, d.trigger)
                store.put(Job(spec, state.copy(nextRunAt = d.at, mode = mode)))
                Log.i(TAG, "schedule id=${spec.id} everyMs=${spec.everyMs} next=${d.at} mode=${mode.wire}")
            }
        }
        WatchdogReceiver.ensureArmed(app)
    }

    fun cancel(app: Context, id: String) {
        AlarmScheduler(app).cancel(id)
        val store = JobStore(app)
        store.remove(id)
        if (store.all().isEmpty()) WatchdogReceiver.cancel(app)
        Log.i(TAG, "cancel id=$id")
    }

    fun requireJob(app: Context, id: String): Job =
        JobStore(app).get(id) ?: throw IllegalArgumentException("unknown job $id")

    fun debugFireIn(app: Context, id: String, delayMs: Long) {
        requireJob(app, id)
        AlarmScheduler(app).armAndRecord(JobStore(app), id, System.currentTimeMillis() + delayMs)
    }

    /** Debug: make the watchdog see a broken chain. */
    fun debugSimulateLostAlarm(app: Context, id: String) {
        val job = requireJob(app, id)
        AlarmScheduler(app).cancel(id)
        JobStore(app).update(id) { it.copy(nextRunAt = System.currentTimeMillis() - 3 * job.spec.everyMs) }
    }
}
