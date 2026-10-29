package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/** The native flow of spec §3 "Alur native saat alarm berbunyi". Main thread only. */
internal object JobRunner {
    private val main = Handler(Looper.getMainLooper())
    private val locks = RunLocks()

    /** [onDone] must be called exactly once; it finishes the broadcast. */
    fun run(app: Context, id: String, trigger: String, scheduledAt: Long, firedAt: Long, onDone: () -> Unit) {
        val store = JobStore(app)
        val job = store.get(id)
        if (job == null) {
            Log.w(TAG, "fire id=$id ignored: job is not scheduled")
            onDone()
            return
        }
        Log.i(TAG, "fire id=$id trigger=$trigger delayMs=${firedAt - scheduledAt}")

        // Prerequisites (spec §3 step 3). A stopped job only comes back through Reconciler (trigger=resumed).
        val missing = PrereqReader.read(app).missing(job.spec.effectiveRequires)
        var runTrigger = trigger
        if (missing.isNotEmpty()) {
            if (job.state.mode == Mode.STOPPED) {
                Log.i(TAG, "skip id=$id: stopped, still missing $missing")
                onDone()
                return
            }
            AlarmScheduler(app).cancel(id)
            store.update(id) { it.copy(mode = Mode.STOPPED, missing = missing, stoppedAt = firedAt, nextRunAt = null) }
            Notifier.showStopped(app)
            runTrigger = Triggers.PREREQUISITE_LOST
            Log.w(TAG, "stop id=$id missing=$missing")
        } else if (job.state.mode == Mode.STOPPED) {
            Log.i(TAG, "skip id=$id: stopped until the app reconciles")
            onDone()
            return
        } else if (trigger != Triggers.MANUAL) {
            // Chain the next alarm before anything below can fail (spec §3 step 2).
            AlarmScheduler(app).armAndRecord(store, id, firedAt + job.spec.everyMs)
        }

        val token = locks.tryAcquire(id, SystemClock.elapsedRealtime(), staleAfterMs = job.spec.timeoutMs * 3)
        if (token == null) {
            Log.w(TAG, "skip id=$id: previous run still busy")
            store.update(id) { it.copy(skippedBusyCount = it.skippedBusyCount + 1) }
            onDone()
            return
        }

        Housekeeping.onJobStart(app)
        val built = ContextBuilder.build(app, store.get(id) ?: job, runTrigger, scheduledAt, firedAt)
        val wakeLock = app.getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dozeless:$id")
            .apply {
                setReferenceCounted(false)
                acquire(job.spec.timeoutMs + 5_000)
            }

        var finished = false
        lateinit var timeout: Runnable
        fun finish(outcome: JobOutcome) {
            if (finished) return
            finished = true
            main.removeCallbacks(timeout)
            val end = System.currentTimeMillis()
            val error = errorOf(outcome)
            store.update(id) {
                it.copy(
                    lastRunAt = firedAt,
                    lastFinishedAt = end,
                    lastDurationMs = end - firedAt,
                    lastError = error,
                    lastTrigger = runTrigger,
                    runCount = it.runCount + 1,
                    ackedEventSeq = EventLogPolicy.nextAck(it.ackedEventSeq, built.deliveredSeq, succeeded = error == null),
                    stoppedAt = if (runTrigger == Triggers.RESUMED && error == null) null else it.stoppedAt,
                )
            }
            EventStore(app).prune(store.all().map { it.state.ackedEventSeq })
            Log.i(TAG, "done id=$id result=${error ?: "ok"} durMs=${end - firedAt}")
            if (wakeLock.isHeld) wakeLock.release()
            onDone()
        }
        timeout = Runnable { finish(JobOutcome.Timeout) }
        main.postDelayed(timeout, job.spec.timeoutMs)

        DartRunner.invoke(app, job.spec.callbackHandle, id, built.map, shouldStart = { !finished }) { outcome ->
            locks.release(id, token)
            finish(outcome)
        }
    }

    private fun errorOf(outcome: JobOutcome): String? = when (outcome) {
        JobOutcome.Success -> null
        JobOutcome.Timeout -> "JOB_TIMEOUT"
        is JobOutcome.Failed -> outcome.error
        is JobOutcome.EngineFailed -> "ENGINE_START_FAILED: ${outcome.error}"
    }
}
