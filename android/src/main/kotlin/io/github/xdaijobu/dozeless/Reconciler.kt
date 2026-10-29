package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.SystemClock
import android.util.Log

internal object ReconcilePolicy {
    enum class Action { NONE, REARM, STOP, RESUME }

    /**
     * Active jobs are always re-armed: a force stop deletes every alarm, but on Android 14 the PendingIntents survive,
     * so "is it armed" cannot be trusted. Re-arming the same PendingIntent replaces the alarm and is harmless.
     */
    fun decide(mode: Mode, missing: List<Prereq>): Action = when {
        mode == Mode.STOPPED && missing.isEmpty() -> Action.RESUME
        mode == Mode.STOPPED -> Action.NONE
        missing.isNotEmpty() -> Action.STOP
        else -> Action.REARM
    }
}

/** Runs when the app starts or comes back to the foreground (Dozeless.initialize and every resume). */
internal object Reconciler {
    fun reconcile(app: Context) {
        ExitInfoReader.collect(app)
        WatchdogReceiver.ensureArmed(app, force = true)
        val dispatched = BootHandler.handleIfNew(app, viaBroadcast = false)
        val store = JobStore(app)
        val scheduler = AlarmScheduler(app)
        val prereqs = PrereqReader.read(app)
        val now = System.currentTimeMillis()
        for (job in store.all()) {
            val id = job.spec.id
            if (id in dispatched) continue
            when (ReconcilePolicy.decide(job.state.mode, prereqs.missing(job.spec.effectiveRequires))) {
                ReconcilePolicy.Action.REARM -> {
                    val at = SchedulePolicy.rearmAt(job.state.nextRunAt, now)
                    scheduler.armAndRecord(store, id, at)
                    Log.i(TAG, "reconcile armed id=$id at=$at")
                }
                ReconcilePolicy.Action.STOP -> JobReceiver.dispatch(app, id, Triggers.PREREQUISITE_LOST)
                ReconcilePolicy.Action.RESUME -> {
                    // Arm right away: resume often fires twice, and a second reconcile must see an armed job.
                    store.update(id) { it.copy(missing = emptyList()) }
                    scheduler.armAndRecord(store, id, now + job.spec.everyMs)
                    JobReceiver.dispatch(app, id, Triggers.RESUMED)
                    Log.i(TAG, "reconcile resumed id=$id")
                }
                ReconcilePolicy.Action.NONE -> Unit
            }
        }
        if (store.all().none { it.state.mode == Mode.STOPPED }) Notifier.clear(app)
    }

    /** Boot or app update: run every active job now; each run re-arms its own chain. */
    fun restartAll(app: Context, trigger: String): Set<String> {
        val ids = JobStore(app).all().filter { it.state.mode != Mode.STOPPED }.map { it.spec.id }.toSet()
        ids.forEach { JobReceiver.dispatch(app, it, trigger) }
        return ids
    }
}

/** Handles each boot exactly once, from BOOT_COMPLETED or, if that never came, from the next app start. */
internal object BootHandler {
    fun handleIfNew(app: Context, viaBroadcast: Boolean): Set<String> {
        val store = JobStore(app)
        val boot = BootInfo.read(app)
        val kind = BootDedupe.classify(store.handledBoot, boot)
        if (kind == BootKind.SAME_BOOT) return emptySet()
        store.handledBoot = boot
        store.timeRef = System.currentTimeMillis() to SystemClock.elapsedRealtime()
        WatchdogReceiver.ensureArmed(app)
        if (kind == BootKind.FIRST_SEEN) return emptySet()

        val lastAlive = store.all().mapNotNull { it.state.lastFinishedAt }.maxOrNull()
        val (shutdownAt, source) = ShutdownGuess.of(store.shutdownMarkerAt, lastAlive, boot.bootTime)
        store.shutdownMarkerAt = null
        EventStore(app).append(
            "boot",
            boot.bootTime,
            mapOf(
                "bootCount" to boot.bootCount?.toLong(),
                "bootTime" to boot.bootTime,
                "shutdownAt" to shutdownAt,
                "shutdownSource" to source,
                "viaBroadcast" to viaBroadcast,
            ),
        )
        Log.i(TAG, "boot bootCount=${boot.bootCount} viaBroadcast=$viaBroadcast shutdown=$source")
        return Reconciler.restartAll(app, Triggers.BOOT)
    }
}
