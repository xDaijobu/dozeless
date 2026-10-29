# dozeless

Background jobs for Flutter on Android that keep running while the phone sleeps: screen off, Doze, killed process, reboot, app update. Built only on `AlarmManager`: no WorkManager, no foreground service, no permanent notification. Your job logic stays in Dart.

```dart
@pragma('vm:entry-point')
Future<void> trackLocation(JobContext ctx) async {
  // runs every minute, even in Doze, in a background FlutterEngine
}

await Dozeless.schedule(id: 'track', callback: trackLocation, every: const Duration(minutes: 1));
```

## Why

- **WorkManager** runs periodic work at most every 15 minutes, and Doze defers it further.
- **Foreground services** keep a notification on screen for as long as they run.
- **`android_alarm_manager_plus`** does not wait for your callback, releases the wake lock too early, skips silently when exact alarms are denied, and its `periodic` alarms are not exact.

dozeless chains one-shot exact alarms (`setExactAndAllowWhileIdle`) per job. The next alarm is armed *before* your callback runs, so a crash or a timeout never breaks the chain. The callback runs in a cached headless FlutterEngine, and the plugin waits for it under its own wake lock.

## Tested

Emulator results (Pixel 9 / Pixel 5 profiles, battery set to *Unrestricted*). Each ✅ means the job kept writing rows to the example app's database in that state.

| Condition | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|
| App open | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| App in background | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Swiped away from Recents | ✅ | ✅ | ✅ | ✅ | ✅ | – |
| Process killed | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Screen off | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Doze (deep idle) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Reboot, app not opened | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Force stop, then app opened | ✅¹ | ✅¹ | ✅¹ | ✅¹ | ✅¹ | ✅¹ |

¹ Android blocks every alarm of a force-stopped app until the user opens it again. That holds for every app, so dozeless cannot run during a force stop. It recovers as soon as the app is opened and reports the stop as a `processExit` event (`USER_REQUESTED`).

Raw evidence (databases written by the jobs, logcat, per-condition logs) is in [`doc/test-results/`](doc/test-results/). Real devices are still to be tested, starting with HyperOS.

## Features

- Exact job chain per job id (minimum interval 1 minute). Falls back to inexact alarms if exact alarms are denied.
- Dart callback awaited with a timeout (≤ 50 s) and a partial wake lock. At most one run per job at a time.
- `schedule()` is idempotent, so calling it on every app start never pushes the next run later.
- Recovery after reboot (`boot`), app update (`packageReplaced`), force stop (on app open) and clock changes (`timeChanged`). An hourly watchdog repairs lost or late chains.
- Prerequisite gate. When location, background location, battery *Unrestricted* or *not Restricted* go missing, the job stops, shows a notification and runs once with `prerequisiteLost`. Once fixed, it resumes with `resumed`.
- Rich `JobContext`: trigger, how late the alarm fired, boot info, Doze, screen, standby bucket, ANDROID_ID, signal levels, and system events since the last run.

## Install

```yaml
dependencies:
  dozeless:
    git:
      url: https://github.com/xDaijobu/dozeless.git
```

Android only. `minSdk` 24. Developed with Flutter 3.47.6 / Dart 3.13.5.

The plugin adds `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK`, `ACCESS_WIFI_STATE`, its receivers and a start-up provider. Your app adds what its jobs need, for example:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Do not use `android:installLocation="preferExternal"`: apps on external storage do not receive `BOOT_COMPLETED`.

## Usage

```dart
import 'package:dozeless/dozeless.dart';
import 'package:flutter/widgets.dart';

@pragma('vm:entry-point')
Future<void> getJob(JobContext ctx) async {
  if (ctx.trigger == JobTrigger.prerequisiteLost) {
    // record "tracking stopped", then return
    return;
  }
  // ctx.delayMs, ctx.device.deviceIdle, ctx.systemEvents, ctx.deadline …
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Dozeless.initialize(
    stopNotification: const StopNotification(
      title: 'Tracking stopped',
      body: 'Open the app to fix permissions or battery settings.',
    ),
  );
  await Dozeless.schedule(
    id: 'get',
    callback: getJob,
    every: const Duration(minutes: 5),
    requires: {Prereq.location, Prereq.backgroundLocation},
    timeout: const Duration(seconds: 45),
  );
  runApp(const MyApp());
}
```

- Callbacks must be top-level or static functions annotated with `@pragma('vm:entry-point')`. Closures are rejected with an `ArgumentError`.
- `Dozeless.initialize()` re-arms everything when the app starts and re-checks prerequisites every time the app is resumed. Call it before `runApp`.
- Other calls: `cancel(id)`, `status(id)`, `runNow(id)`, `checkPrerequisites()`, `openSettings(Setting)`, and `debugFireIn`, `debugSimulateLostAlarm`, `debugRunWatchdog` for testing.

### Prerequisites

Battery *Unrestricted* and *not Restricted* are required for every job on every Android version. On Android 14+, battery *Unrestricted* is also what allows exact alarms, so the app never has to ask for `SCHEDULE_EXACT_ALARM`.

```dart
final p = await Dozeless.checkPrerequisites();
if (!p.batteryUnrestricted) await Dozeless.openSettings(Setting.batteryOptimization);
if (p.autostartSettingAvailable) await Dozeless.openSettings(Setting.autostart); // Xiaomi, Oppo, Realme, Vivo
```

| Prerequisite | Blocks jobs | How the user grants it |
|---|---|---|
| `location` | if the job requires it | runtime dialog |
| `backgroundLocation` | if the job requires it | Settings → "Allow all the time" |
| `batteryUnrestricted` | always | `Setting.batteryOptimization` or `Setting.appDetails` |
| `notBackgroundRestricted` | always | App info → Battery → not "Restricted" |
| `exactAlarm` | never (falls back to inexact) | granted by battery *Unrestricted* |
| `notification` | never | runtime dialog (Android 13+) |

### JobContext

| Field | Meaning |
|---|---|
| `trigger` | `alarm` · `boot` · `watchdog` · `packageReplaced` · `timeChanged` · `prerequisiteLost` · `resumed` · `manual` |
| `scheduledAt`, `firedAt`, `delayMs` | when the alarm was due, when it fired, how late |
| `timeout`, `deadline` | stop working before `deadline`; the plugin gives up there |
| `mode` | `exact` · `inexact` · `stopped` |
| `boot` | `bootCount`, `bootTime`, `firstJobSinceBoot` |
| `systemEvents` | events since this job's last successful run (delivered again if the run fails) |
| `prerequisites`, `device` | snapshots taken just before the run |
| `lastRunAt`, `lastError`, `stoppedAt` | previous run, and when a resumed job had stopped |

### System events

| `type` | `data` |
|---|---|
| `boot` | `bootCount`, `bootTime`, `shutdownAt`, `shutdownSource` (`marker` · `lastJob` · `unknown`), `viaBroadcast` |
| `timeChanged` | `jumpMs`, `autoTime` |
| `timezoneChanged` | `from`, `to` |
| `processExit` | `reason` (`USER_REQUESTED` = force stop, `LOW_MEMORY`, `CRASH`, …), `reasonCode`, `importance`, `description` |

### `JobStatus.lastError`

| Value | Meaning |
|---|---|
| `JOB_TIMEOUT` | the callback did not finish in time; later runs are skipped as busy until it returns or 3× the timeout passes |
| `JOB_FAILED: …` | the callback threw |
| `CALLBACK_NOT_FOUND: …` | the callback handle is not in this build |
| `ENGINE_START_FAILED: …` | the app was never opened since install, or the dispatcher was not ready within 15 s |

## Known limits

- **Force stop** stops everything until the app is opened again (Android rule, see above).
- **Xiaomi/HyperOS and other OEMs** may treat "swipe away" or their cleaner like a force stop, and may block `BOOT_COMPLETED` without Autostart. Ask users to enable Autostart and lock the app in Recents.
- **Location in the background can be stale.** Android 8+ gives background apps a fresh location only a few times per hour, so `getCurrentPosition` may return a cached fix with no error. Record the fix time and treat old fixes as stale.
- Runs of different jobs in one process are serialized by Android's broadcast queue. Keep timeouts short.

## Debugging

```bash
adb logcat -s Dozeless:I flutter:I
adb shell dumpsys alarm | grep -A3 dozeless://        # one alarm per job
adb shell dumpsys alarm | grep -A4 dozeless.WATCHDOG  # hourly watchdog
adb shell dumpsys deviceidle whitelist +<package>     # battery Unrestricted, for tests
adb shell dumpsys deviceidle force-idle               # force Doze (screen off, unplugged)
```

Job callbacks run in a separate engine, so hot reload does not reach them. Use hot restart or kill the app process after changing a job.

## Tests

```bash
flutter test                                  # Dart API, models, dispatcher
cd example && flutter test                    # example statistics
cd example && flutter build apk --config-only && cd android && ./gradlew :dozeless:testDebugUnitTest   # Kotlin (JDK 17+)
cd example && flutter test integration_test/dozeless_test.dart -d <device> --no-uninstall
```

Integration tests need battery *Unrestricted* for the example app (`adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example`). `--no-uninstall` keeps that setting between runs.

## Documentation

`doc/` is in Indonesian: the design spec, the implementation plan (task by task, TDD), test results per Android version, and a one-page summary (`doc/ringkasan.html`). `doc/internal/` holds notes about the app this plugin was extracted from and is not published.

## License

Not chosen yet. A license is required before publishing to pub.dev.
