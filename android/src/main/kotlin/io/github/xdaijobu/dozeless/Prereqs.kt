package io.github.xdaijobu.dozeless

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager

/** What the device allows right now. */
internal data class PrereqSnapshot(
    val location: Boolean,
    val backgroundLocation: Boolean,
    val batteryUnrestricted: Boolean,
    val backgroundRestricted: Boolean,
    val exactAlarm: Boolean,
    val notification: Boolean,
    val autostartSettingAvailable: Boolean,
    // Not blocking: the optional device admin that disables Settings' "Force stop" button.
    val forceStopGuard: Boolean = false,
    val forceStopGuardAvailable: Boolean = false,
) {
    fun has(p: Prereq): Boolean = when (p) {
        Prereq.LOCATION -> location
        Prereq.BACKGROUND_LOCATION -> backgroundLocation
        Prereq.BATTERY_UNRESTRICTED -> batteryUnrestricted
        Prereq.NOT_BACKGROUND_RESTRICTED -> !backgroundRestricted
    }

    /** Blocking prerequisites that are missing, in [Prereq] order. Exact alarm and notification never block. */
    fun missing(required: Set<Prereq>): List<Prereq> = Prereq.entries.filter { it in required && !has(it) }

    fun toMap(): Map<String, Any?> = mapOf(
        "location" to location,
        "backgroundLocation" to backgroundLocation,
        "batteryUnrestricted" to batteryUnrestricted,
        "backgroundRestricted" to backgroundRestricted,
        "exactAlarm" to exactAlarm,
        "notification" to notification,
        "autostartSettingAvailable" to autostartSettingAvailable,
        "forceStopGuard" to forceStopGuard,
        "forceStopGuardAvailable" to forceStopGuardAvailable,
    )
}

internal object PrereqReader {
    fun read(context: Context): PrereqSnapshot {
        val fine = granted(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val background = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else {
            fine
        }
        val power = context.getSystemService(PowerManager::class.java)
        val activity = context.getSystemService(ActivityManager::class.java)
        val notifications = context.getSystemService(NotificationManager::class.java)
        val notificationAllowed = notifications.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || granted(context, Manifest.permission.POST_NOTIFICATIONS))
        return PrereqSnapshot(
            location = fine,
            backgroundLocation = background,
            batteryUnrestricted = power.isIgnoringBatteryOptimizations(context.packageName),
            backgroundRestricted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && activity.isBackgroundRestricted,
            exactAlarm = AlarmScheduler(context).canExact(),
            notification = notificationAllowed,
            autostartSettingAvailable = AutostartIntents.candidates(Build.MANUFACTURER).isNotEmpty(),
            forceStopGuard = ForceStopGuard.active(context),
            forceStopGuardAvailable = ForceStopGuard.available(context),
        )
    }

    private fun granted(context: Context, permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
}
