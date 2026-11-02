package io.github.xdaijobu.dozeless

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log

/**
 * Optional device admin with no policies; the app opts in by declaring it in its manifest. While it is active,
 * Settings disables the app's "Force stop" button. Recents, OEM cleaners and `adb shell am force-stop` are not
 * affected.
 */
class DozelessAdminReceiver : DeviceAdminReceiver() {
    override fun onEnabled(context: Context, intent: Intent) {
        Log.i(TAG, "device admin enabled")
        ForceStopGuard.applyOwnerPolicy(context.applicationContext)
    }

    override fun onDisabled(context: Context, intent: Intent) {
        Log.i(TAG, "device admin disabled")
    }
}

internal object ForceStopGuard {
    fun component(context: Context) = ComponentName(context, DozelessAdminReceiver::class.java)

    /** The app declared [DozelessAdminReceiver]. */
    fun available(context: Context): Boolean = try {
        context.packageManager.getReceiverInfo(component(context), 0)
        true
    } catch (e: PackageManager.NameNotFoundException) {
        false
    }

    fun active(context: Context): Boolean = available(context) && dpm(context).isAdminActive(component(context))

    fun deviceOwner(context: Context): Boolean = dpm(context).isDeviceOwnerApp(context.packageName)

    /** The system dialog that asks the user to activate the admin. Null when the app did not declare it. */
    fun activationIntent(context: Context): Intent? = if (!available(context)) {
        null
    } else {
        Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, component(context))
    }

    fun deactivate(context: Context) {
        if (!active(context)) return
        try {
            dpm(context).removeActiveAdmin(component(context))
        } catch (e: SecurityException) {
            // A device owner cannot remove itself this way.
            Log.w(TAG, "device admin not removed", e)
        }
    }

    /** Device owner only (Android 11+): also blocks force stop and clear data on every Settings page. */
    fun applyOwnerPolicy(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R || !active(context) || !deviceOwner(context)) return
        val dpm = dpm(context)
        val admin = component(context)
        val pkg = context.packageName
        try {
            val disabled = dpm.getUserControlDisabledPackages(admin)
            if (pkg in disabled) return
            dpm.setUserControlDisabledPackages(admin, disabled + pkg)
            Log.i(TAG, "device owner: user control disabled for $pkg")
        } catch (e: SecurityException) {
            // The app owns the device through another admin component.
            Log.w(TAG, "user control not disabled", e)
        }
    }

    private fun dpm(context: Context) = context.getSystemService(DevicePolicyManager::class.java)
}
