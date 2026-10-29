package io.github.xdaijobu.dozeless

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONException

/** Jobs and plugin bookkeeping in SharedPreferences. Writes use commit() so they survive a process kill. */
internal class JobStore(context: Context) {
    private val prefs = context.getSharedPreferences("dozeless", Context.MODE_PRIVATE)

    fun all(): List<Job> = prefs.all
        .filterKeys { it.startsWith(JOB_PREFIX) }
        .values
        .mapNotNull { (it as? String)?.let(::decodeOrNull) }

    fun get(id: String): Job? = prefs.getString(JOB_PREFIX + id, null)?.let(::decodeOrNull)

    fun put(job: Job) = edit { putString(JOB_PREFIX + job.spec.id, JobCodec.encode(job)) }

    fun update(id: String, change: (JobState) -> JobState): Job? {
        val job = get(id) ?: return null
        return job.copy(state = change(job.state)).also(::put)
    }

    fun remove(id: String) = edit { remove(JOB_PREFIX + id) }

    var dispatcherHandle: Long
        get() = prefs.getLong(KEY_DISPATCHER, 0L)
        set(value) = edit { putLong(KEY_DISPATCHER, value) }

    var handledBoot: BootInfo?
        get() = longOrNull(KEY_BOOT_TIME)?.let { BootInfo(prefs.getInt(KEY_BOOT_COUNT, -1).takeIf { c -> c >= 0 }, it) }
        set(value) = edit {
            putInt(KEY_BOOT_COUNT, value?.bootCount ?: -1)
            putLong(KEY_BOOT_TIME, value?.bootTime ?: 0L)
        }

    var stopText: StopText
        get() = StopText(
            title = prefs.getString(KEY_NOTIFY_TITLE, null) ?: "Proses latar belakang berhenti",
            body = prefs.getString(KEY_NOTIFY_BODY, null) ?: "Buka aplikasi untuk memperbaiki pengaturan.",
            channelName = prefs.getString(KEY_NOTIFY_CHANNEL, null) ?: "Status latar belakang",
        )
        set(value) = edit {
            putString(KEY_NOTIFY_TITLE, value.title)
            putString(KEY_NOTIFY_BODY, value.body)
            putString(KEY_NOTIFY_CHANNEL, value.channelName)
        }

    /** Wall clock and elapsedRealtime read at the same moment, to measure clock jumps. */
    var timeRef: Pair<Long, Long>?
        get() = longOrNull(KEY_REF_WALL)?.let { it to prefs.getLong(KEY_REF_ELAPSED, 0L) }
        set(value) {
            if (value != null) edit { putLong(KEY_REF_WALL, value.first).putLong(KEY_REF_ELAPSED, value.second) }
        }

    var lastTimezone: String?
        get() = prefs.getString(KEY_TIMEZONE, null)
        set(value) = edit { putString(KEY_TIMEZONE, value) }

    var shutdownMarkerAt: Long?
        get() = longOrNull(KEY_SHUTDOWN)
        set(value) = edit { if (value == null) remove(KEY_SHUTDOWN) else putLong(KEY_SHUTDOWN, value) }

    var lastExitReadAt: Long?
        get() = longOrNull(KEY_EXIT_READ)
        set(value) {
            if (value != null) edit { putLong(KEY_EXIT_READ, value) }
        }

    private fun edit(change: SharedPreferences.Editor.() -> Unit) {
        prefs.edit().apply(change).commit()
    }

    private fun longOrNull(key: String): Long? = if (prefs.contains(key)) prefs.getLong(key, 0L) else null

    private fun decodeOrNull(json: String): Job? = try {
        JobCodec.decode(json)
    } catch (e: JSONException) {
        Log.w(TAG, "dropping unreadable job: $json", e)
        null
    }

    private companion object {
        const val JOB_PREFIX = "job:"
        const val KEY_DISPATCHER = "dispatcherHandle"
        const val KEY_BOOT_COUNT = "handledBootCount"
        const val KEY_BOOT_TIME = "handledBootTime"
        const val KEY_NOTIFY_TITLE = "notifyTitle"
        const val KEY_NOTIFY_BODY = "notifyBody"
        const val KEY_NOTIFY_CHANNEL = "notifyChannel"
        const val KEY_REF_WALL = "timeRefWall"
        const val KEY_REF_ELAPSED = "timeRefElapsed"
        const val KEY_TIMEZONE = "lastTimezone"
        const val KEY_SHUTDOWN = "shutdownMarkerAt"
        const val KEY_EXIT_READ = "lastExitReadAt"
    }
}
