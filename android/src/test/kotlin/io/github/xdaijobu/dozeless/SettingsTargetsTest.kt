package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

internal class SettingsTargetsTest {
    private val appDetails = SettingsTarget.Action("android.settings.APPLICATION_DETAILS_SETTINGS", withPackage = true)

    @Test
    fun batteryOpensTheOptimizationListThenFallsBackToAppDetails() = assertEquals(
        listOf(SettingsTarget.Action("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS", withPackage = false), appDetails),
        SettingsTargets.of("batteryOptimization", 34, "Xiaomi"),
    )

    @Test
    fun exactAlarmPageOnlyExistsFromAndroid12() {
        assertEquals(listOf(appDetails), SettingsTargets.of("exactAlarm", 30, "Xiaomi"))
        assertEquals("android.settings.REQUEST_SCHEDULE_EXACT_ALARM", (SettingsTargets.of("exactAlarm", 31, "Xiaomi").first() as SettingsTarget.Action).action)
    }

    @Test
    fun autostartMatchesBrandIgnoringCase() = assertEquals(
        listOf(SettingsTarget.Component("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
        SettingsTargets.of("autostart", 34, "XIAOMI"),
    )

    @Test
    fun autostartIsEmptyForBrandsWithoutSuchPage() =
        assertTrue(SettingsTargets.of("autostart", 34, "samsung").isEmpty())

    @Test
    fun forceStopGuardOpensTheDeviceAdminDialog() =
        assertEquals(listOf(SettingsTarget.DeviceAdmin), SettingsTargets.of("forceStopGuard", 34, "samsung"))

    @Test
    fun unknownSettingIsRejected() {
        assertFailsWith<IllegalArgumentException> { SettingsTargets.of("wifi", 34, "Xiaomi") }
    }
}
