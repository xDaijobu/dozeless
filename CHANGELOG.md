## Unreleased

* The default `StopNotification` text is now English: title `Background work stopped`, body `Open the app to fix its permissions or battery settings.`, channel name `Background status`.

## 0.1.0

* Exact-alarm job chain per job id with an inexact fallback, re-armed before every run.
* Dart job callbacks run in a cached headless FlutterEngine and are awaited, with a timeout and a wake lock.
* Prerequisites (location, background location, battery unrestricted, not background-restricted), stop and resume with a notification.
* Recovery after boot, app update, force stop and clock changes; hourly watchdog. On Android 15+ this includes the `BOOT_COMPLETED` the system sends without a reboot when a user action ends the force-stopped state.
* System events for jobs: `boot`, `timeChanged`, `timezoneChanged`, `processExit`.
* Optional Quick Settings tile (`DozelessTileService`) that repairs every job, also after a force stop, without opening the app.
* Optional force-stop guard (`DozelessAdminReceiver`, `Setting.forceStopGuard`, `Dozeless.disableForceStopGuard()`): a device admin without policies, so Settings disables "Force stop". As device owner it also sets `setUserControlDisabledPackages`. Its state is in `PrerequisiteStatus.forceStopGuard` and `forceStopGuardAvailable`.
