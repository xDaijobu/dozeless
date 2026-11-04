package io.github.xdaijobu.dozeless

import android.annotation.SuppressLint
import android.app.usage.UsageStatsManager
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.TelephonyManager
import java.util.TimeZone

/** Device facts for `JobContext.device` and the record's Jam/Perangkat/Sistem fields. */
internal object DeviceState {
    @SuppressLint("HardwareIds")
    fun read(context: Context): Map<String, Any?> {
        val power = context.getSystemService(PowerManager::class.java)
        return mapOf(
            "deviceId" to Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID),
            "deviceIdle" to power.isDeviceIdleMode,
            "interactive" to power.isInteractive,
            "powerSaveMode" to power.isPowerSaveMode,
            "standbyBucket" to standbyBucket(context),
            "autoTime" to (Settings.Global.getInt(context.contentResolver, Settings.Global.AUTO_TIME, 1) == 1),
            "timezone" to TimeZone.getDefault().id,
            "cellLevel" to cellLevel(context),
            "wifiLevel" to wifiLevel(context),
        )
    }

    private fun standbyBucket(context: Context): String =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) "unknown"
        else StandbyBuckets.name(context.getSystemService(UsageStatsManager::class.java).appStandbyBucket)

    private fun cellLevel(context: Context): Int? = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) null
        else context.getSystemService(TelephonyManager::class.java)?.signalStrength?.level
    } catch (e: SecurityException) {
        null
    }

    @Suppress("DEPRECATION")
    private fun wifiLevel(context: Context): Int? = try {
        val rssi = context.getSystemService(WifiManager::class.java)?.connectionInfo?.rssi
        if (rssi == null || rssi <= -127) null else WifiManager.calculateSignalLevel(rssi, 5)
    } catch (e: SecurityException) {
        null
    }
}

internal object StandbyBuckets {
    fun name(bucket: Int): String = when (bucket) {
        5 -> "exempted"
        10 -> "active"
        20 -> "workingSet"
        30 -> "frequent"
        40 -> "rare"
        45 -> "restricted"
        50 -> "never"
        else -> "unknown"
    }
}
