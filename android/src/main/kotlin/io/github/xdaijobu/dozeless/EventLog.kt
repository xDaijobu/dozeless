package io.github.xdaijobu.dozeless

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/** Something the plugin saw outside a job run; delivered once to every job through `ctx.systemEvents`. */
internal data class SystemEvent(val seq: Long, val type: String, val at: Long, val data: Map<String, Any?>)

internal object EventLogPolicy {
    const val MAX_EVENTS = 500

    fun append(events: List<SystemEvent>, lastSeq: Long, type: String, at: Long, data: Map<String, Any?>): Pair<List<SystemEvent>, Long> {
        val seq = lastSeq + 1
        return (events + SystemEvent(seq, type, at, data)).takeLast(MAX_EVENTS) to seq
    }

    fun pending(events: List<SystemEvent>, ackedSeq: Long): List<SystemEvent> = events.filter { it.seq > ackedSeq }

    /** A failed run acknowledges nothing, so the same events are delivered again next time. */
    fun nextAck(acked: Long, delivered: Long, succeeded: Boolean): Long = if (succeeded) maxOf(acked, delivered) else acked

    /** Keeps what at least one job has not acknowledged yet. */
    fun prune(events: List<SystemEvent>, ackedSeqs: Collection<Long>): List<SystemEvent> {
        val min = ackedSeqs.minOrNull() ?: return emptyList()
        return events.filter { it.seq > min }
    }
}

internal object EventCodec {
    fun encodeAll(events: List<SystemEvent>): String = JSONArray(
        events.map { e ->
            val data = JSONObject()
            e.data.forEach { (k, v) -> data.put(k, v ?: JSONObject.NULL) }
            JSONObject().put("seq", e.seq).put("type", e.type).put("at", e.at).put("data", data)
        },
    ).toString()

    fun decodeAll(json: String?): List<SystemEvent> {
        if (json.isNullOrEmpty()) return emptyList()
        val array = JSONArray(json)
        return List(array.length()) { i ->
            val o = array.getJSONObject(i)
            val d = o.getJSONObject("data")
            SystemEvent(
                seq = o.getLong("seq"),
                type = o.getString("type"),
                at = o.getLong("at"),
                data = d.keys().asSequence().associateWith { k ->
                    when (val v = d.get(k)) {
                        JSONObject.NULL -> null
                        is Int -> v.toLong()
                        else -> v
                    }
                },
            )
        }
    }

    fun toMap(e: SystemEvent): Map<String, Any?> = mapOf("seq" to e.seq, "type" to e.type, "at" to e.at, "data" to e.data)
}

internal class EventStore(context: Context) {
    private val prefs = context.getSharedPreferences("dozeless_events", Context.MODE_PRIVATE)

    val lastSeq: Long get() = prefs.getLong(KEY_LAST_SEQ, 0L)

    fun all(): List<SystemEvent> = EventCodec.decodeAll(prefs.getString(KEY_EVENTS, null))

    fun append(type: String, at: Long, data: Map<String, Any?>) {
        val (events, seq) = EventLogPolicy.append(all(), lastSeq, type, at, data)
        prefs.edit().putString(KEY_EVENTS, EventCodec.encodeAll(events)).putLong(KEY_LAST_SEQ, seq).commit()
        Log.i(TAG, "event #$seq $type $data")
    }

    fun pendingFor(ackedSeq: Long): List<SystemEvent> = EventLogPolicy.pending(all(), ackedSeq)

    fun prune(ackedSeqs: Collection<Long>) {
        prefs.edit().putString(KEY_EVENTS, EventCodec.encodeAll(EventLogPolicy.prune(all(), ackedSeqs))).commit()
    }

    private companion object {
        const val KEY_EVENTS = "events"
        const val KEY_LAST_SEQ = "lastSeq"
    }
}
