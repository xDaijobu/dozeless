package io.github.xdaijobu.dozeless

import org.json.JSONArray
import org.json.JSONObject

/** Stores jobs as JSON strings and turns them into status maps for Dart. */
internal object JobCodec {
    fun encode(job: Job): String {
        val s = job.state
        return JSONObject()
            .put("id", job.spec.id)
            .put("callbackHandle", job.spec.callbackHandle)
            .put("everyMs", job.spec.everyMs)
            .put("timeoutMs", job.spec.timeoutMs)
            .put("requires", JSONArray(job.spec.requires.map { it.wire }.sorted()))
            .put("mode", s.mode.wire)
            .putOpt("nextRunAt", s.nextRunAt)
            .putOpt("lastRunAt", s.lastRunAt)
            .putOpt("lastFinishedAt", s.lastFinishedAt)
            .putOpt("lastDurationMs", s.lastDurationMs)
            .putOpt("lastError", s.lastError)
            .putOpt("lastTrigger", s.lastTrigger)
            .put("runCount", s.runCount)
            .put("skippedBusyCount", s.skippedBusyCount)
            .put("ackedEventSeq", s.ackedEventSeq)
            .put("missing", JSONArray(s.missing.map { it.wire }))
            .putOpt("stoppedAt", s.stoppedAt)
            .toString()
    }

    fun decode(json: String): Job {
        val o = JSONObject(json)
        val spec = JobSpec(
            id = o.getString("id"),
            callbackHandle = o.getLong("callbackHandle"),
            everyMs = o.getLong("everyMs"),
            timeoutMs = o.getLong("timeoutMs"),
            requires = o.optJSONArray("requires").strings().mapNotNull { Prereq.fromWire(it) }.toSet(),
        )
        val state = JobState(
            mode = Mode.fromWire(o.optString("mode")),
            nextRunAt = o.longOrNull("nextRunAt"),
            lastRunAt = o.longOrNull("lastRunAt"),
            lastFinishedAt = o.longOrNull("lastFinishedAt"),
            lastDurationMs = o.longOrNull("lastDurationMs"),
            lastError = o.stringOrNull("lastError"),
            lastTrigger = o.stringOrNull("lastTrigger"),
            runCount = o.optLong("runCount"),
            skippedBusyCount = o.optLong("skippedBusyCount"),
            ackedEventSeq = o.optLong("ackedEventSeq"),
            missing = o.optJSONArray("missing").strings().mapNotNull { Prereq.fromWire(it) },
            stoppedAt = o.longOrNull("stoppedAt"),
        )
        return Job(spec, state)
    }

    fun statusMap(job: Job): Map<String, Any?> = mapOf(
        "id" to job.spec.id,
        "mode" to job.state.mode.wire,
        "nextRunAt" to job.state.nextRunAt,
        "lastRunAt" to job.state.lastRunAt,
        "lastFinishedAt" to job.state.lastFinishedAt,
        "lastDurationMs" to job.state.lastDurationMs,
        "lastError" to job.state.lastError,
        "lastTrigger" to job.state.lastTrigger,
        "runCount" to job.state.runCount,
        "skippedBusyCount" to job.state.skippedBusyCount,
        "missing" to job.state.missing.map { it.wire },
        "stoppedAt" to job.state.stoppedAt,
    )

    private fun JSONObject.longOrNull(key: String): Long? = if (has(key) && !isNull(key)) getLong(key) else null

    private fun JSONObject.stringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

    private fun JSONArray?.strings(): List<String> = if (this == null) emptyList() else List(length()) { getString(it) }
}
