## 0.1.0

* Exact-alarm job chain per job id with an inexact fallback, re-armed before every run.
* Dart job callbacks run in a cached headless FlutterEngine and are awaited, with a timeout and a wake lock.
* Prerequisites (location, background location, battery unrestricted, not background-restricted), stop and resume with a notification.
* Recovery after boot, app update, force stop and clock changes; hourly watchdog.
* System events for jobs: `boot`, `timeChanged`, `timezoneChanged`, `processExit`.
