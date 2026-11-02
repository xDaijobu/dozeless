## Unreleased

* Android 15+: re-arm every job when `BOOT_COMPLETED` arrives without a reboot, which is how the system tells an app that a user action ended its force-stopped state.
* Optional Quick Settings tile (`DozelessTileService`) that repairs every job, also after a force stop, without opening the app.
* Optional force-stop guard (`DozelessAdminReceiver`, `Setting.forceStopGuard`, `Dozeless.disableForceStopGuard()`): a device admin without policies, so Settings disables "Force stop". As device owner it also sets `setUserControlDisabledPackages`.
* `PrerequisiteStatus.forceStopGuard` and `forceStopGuardAvailable`.

## 0.1.0

* Exact-alarm job chain per job id with an inexact fallback, re-armed before every run.
* Dart job callbacks run in a cached headless FlutterEngine and are awaited, with a timeout and a wake lock.
* Prerequisites (location, background location, battery unrestricted, not background-restricted), stop and resume with a notification.
* Recovery after boot, app update, force stop and clock changes; hourly watchdog.
* System events for jobs: `boot`, `timeChanged`, `timezoneChanged`, `processExit`.
