package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.util.Log

/**
 * Its onCreate runs every time the app process starts, including when an alarm wakes it, so the runtime-only
 * ACTION_SHUTDOWN receiver is registered whenever the process is alive (spec §3 ProcessStartHook).
 */
class ProcessStartHook : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.applicationContext?.let(ShutdownWatcher::register)
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}

internal object ShutdownWatcher {
    private var registered = false

    fun register(app: Context) {
        if (registered) return
        registered = true
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                JobStore(context).shutdownMarkerAt = System.currentTimeMillis()
                Log.i(TAG, "shutdown marker written")
            }
        }
        val filter = IntentFilter(Intent.ACTION_SHUTDOWN)
        // ACTION_SHUTDOWN is a protected broadcast: only the system can send it, so exporting is safe.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            app.registerReceiver(receiver, filter)
        }
    }
}
