package io.github.xdaijobu.dozeless

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log

/** OEM "Autostart" pages. Without Autostart these brands do not deliver BOOT_COMPLETED (spec §4). */
internal object AutostartIntents {
    fun candidates(manufacturer: String): List<Pair<String, String>> = when (manufacturer.lowercase()) {
        "xiaomi", "redmi", "poco" -> listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        "oppo", "realme" -> listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        )
        "vivo" -> listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        )
        else -> emptyList()
    }
}

/** A settings page to try, in order, until one opens. */
internal sealed interface SettingsTarget {
    data class Action(val action: String, val withPackage: Boolean) : SettingsTarget
    data class Component(val pkg: String, val cls: String) : SettingsTarget

    /** The system dialog that activates [DozelessAdminReceiver]. It refuses to open in a new task. */
    data object DeviceAdmin : SettingsTarget
}

internal object SettingsTargets {
    private val appDetails = SettingsTarget.Action("android.settings.APPLICATION_DETAILS_SETTINGS", withPackage = true)

    fun of(setting: String, sdk: Int, manufacturer: String): List<SettingsTarget> = when (setting) {
        "batteryOptimization" -> listOf(SettingsTarget.Action("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS", withPackage = false), appDetails)
        "appDetails" -> listOf(appDetails)
        "exactAlarm" -> if (sdk >= Build.VERSION_CODES.S) {
            listOf(SettingsTarget.Action("android.settings.REQUEST_SCHEDULE_EXACT_ALARM", withPackage = true), appDetails)
        } else {
            listOf(appDetails)
        }
        "autostart" -> AutostartIntents.candidates(manufacturer).map { SettingsTarget.Component(it.first, it.second) }
        "forceStopGuard" -> listOf(SettingsTarget.DeviceAdmin)
        else -> throw IllegalArgumentException("unknown setting $setting")
    }
}

internal object SettingsOpener {
    /** Opens the first page that exists. Returns false if none could be opened. */
    fun open(context: Context, setting: String, activity: Activity?): Boolean {
        for (target in SettingsTargets.of(setting, Build.VERSION.SDK_INT, Build.MANUFACTURER)) {
            val intent = when (target) {
                is SettingsTarget.Action -> Intent(target.action).apply {
                    if (target.withPackage) data = Uri.parse("package:${context.packageName}")
                }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                is SettingsTarget.Component -> Intent().setComponent(ComponentName(target.pkg, target.cls)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                SettingsTarget.DeviceAdmin -> ForceStopGuard.activationIntent(context) ?: continue
            }
            val starter = if (target == SettingsTarget.DeviceAdmin) activity ?: continue else context
            try {
                starter.startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                Log.i(TAG, "settings target not found: $target")
            } catch (e: SecurityException) {
                Log.i(TAG, "settings target not allowed: $target")
            }
        }
        return false
    }
}
