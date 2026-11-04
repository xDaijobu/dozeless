package io.github.xdaijobu.dozeless

import android.content.Context

internal class BuiltContext(val map: Map<String, Any?>, val deliveredSeq: Long)

/** Builds the map that becomes `JobContext` in Dart. */
internal object ContextBuilder {
    fun build(app: Context, job: Job, trigger: String, scheduledAt: Long, firedAt: Long): BuiltContext {
        val boot = BootInfo.read(app)
        val s = job.state
        val events = EventStore(app).pendingFor(s.ackedEventSeq)
        val map = mapOf(
            "jobId" to job.spec.id,
            "trigger" to trigger,
            "scheduledAt" to scheduledAt,
            "firedAt" to firedAt,
            "delayMs" to firedAt - scheduledAt,
            "timeoutMs" to job.spec.timeoutMs,
            "mode" to s.mode.wire,
            "lastRunAt" to s.lastRunAt,
            "lastError" to s.lastError,
            "stoppedAt" to s.stoppedAt,
            "boot" to mapOf(
                "bootCount" to boot.bootCount,
                "bootTime" to boot.bootTime,
                "firstJobSinceBoot" to boot.isFirstRunSinceBoot(s.lastRunAt),
            ),
            "systemEvents" to events.map(EventCodec::toMap),
            "prerequisites" to PrereqReader.read(app).toMap(),
            "device" to DeviceState.read(app),
        )
        return BuiltContext(map, deliveredSeq = events.maxOfOrNull { it.seq } ?: s.ackedEventSeq)
    }
}
