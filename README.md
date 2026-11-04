# dozeless

**Run Dart background jobs on Android every minute, even in Doze, with no foreground service and no permanent notification.**

[![pub package](https://img.shields.io/pub/v/dozeless.svg)](https://pub.dev/packages/dozeless)
[![CI](https://github.com/xDaijobu/dozeless/actions/workflows/ci.yaml/badge.svg)](https://github.com/xDaijobu/dozeless/actions/workflows/ci.yaml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue)](https://github.com/xDaijobu/dozeless/blob/main/LICENSE)
![Platform: Android](https://img.shields.io/badge/platform-Android-3DDC84)
![minSdk 24](https://img.shields.io/badge/minSdk-24-blue)

- **Every minute, even in Doze.** One-shot exact alarms keep firing with the screen off and in deep idle.
- **No foreground service, no permanent notification.** Built only on `AlarmManager`, without WorkManager. A notification appears only when a job stops for a missing prerequisite.
- **Your job logic stays in Dart.** Callbacks run in a background FlutterEngine, and dozeless waits for them with a wake lock and a timeout.
- **Survives a killed process, a reboot and an app update.** Jobs come back without the app being opened.
- **Recovers from a force stop.** Android blocks every alarm until a user action brings the app back. Opening the app re-arms every job; on Android 15+ other user actions that end the stopped state do too. Two opt-in helpers go further: a Quick Settings tile that re-arms them without opening the app, and a guard that disables Settings' **Force stop** button.

Tested on emulators, Android 11 to 16. Real devices are still to be tested, starting with HyperOS, where a first forced-Doze check saw late alarms. See [Tested](#tested) and [Known limits](#known-limits).

## Quick start

**1. Add the package.** Android only, `minSdk` 24. Needs Dart `^3.13.5`; developed with Flutter 3.47.6 / Dart 3.13.5.

```bash
flutter pub add dozeless
```

**2. Check the manifest.** The plugin adds `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK`, `ACCESS_WIFI_STATE`, its receivers and a start-up provider, so the job below needs nothing more. Your app adds what its own jobs need, for example:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

> **Warning:** do not use `android:installLocation="preferExternal"`: apps on external storage do not receive `BOOT_COMPLETED`.

**3. Schedule a job** before `runApp`.

```dart
import 'package:dozeless/dozeless.dart';
import 'package:flutter/widgets.dart';

@pragma('vm:entry-point')
Future<void> heartbeat(JobContext ctx) async {
  // Runs every minute, even in Doze, in a background FlutterEngine.
  debugPrint('${ctx.trigger.name}: ${ctx.delayMs} ms late, Doze ${ctx.device.deviceIdle}');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Dozeless.initialize();
  await Dozeless.schedule(id: 'heartbeat', callback: heartbeat, every: const Duration(minutes: 1));
  runApp(const MyApp());
}
```

**4. Allow it and watch it.** Every job needs battery *Unrestricted*. For a quick test, start the app and run this within a minute, before the first alarm fires:

```bash
adb shell dumpsys deviceidle whitelist +<package>   # battery Unrestricted, for tests
adb logcat -s Dozeless:I flutter:I
```

A job whose alarm fires without it stops, and shows a notification if the app may post them. It resumes once the setting is fixed and the app comes back to the foreground. In a real app, ask the user: see [Prerequisites](#prerequisites).

## Screenshots

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/xDaijobu/dozeless/main/doc/screenshots/example-overview.png" width="250" alt="Example app, Overview tab: job status, a card per job and the setup checklist"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/xDaijobu/dozeless/main/doc/screenshots/example-runs.png" width="250" alt="Example app, Runs tab: timeline of the last 24 hours of runs"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/xDaijobu/dozeless/main/doc/screenshots/example-lab.png" width="250" alt="Example app, Lab tab: screen-off test statistics and debug actions"></td>
  </tr>
  <tr>
    <td align="center"><sub>Overview: job status, jobs, setup checklist</sub></td>
    <td align="center"><sub>Runs: the last 24 h of runs</sub></td>
    <td align="center"><sub>Lab: test statistics, debug actions</sub></td>
  </tr>
</table>

<sub>The [example app](#example-app) on a POCO X6 Pro, Android 16, HyperOS 3. These are screenshots, not test results: see [Tested](#tested).</sub>

## Contents

- [Quick start](#quick-start)
- [Screenshots](#screenshots)
- [Why dozeless](#why-dozeless)
- [How it works](#how-it-works)
- [Tested](#tested)
- [Features](#features)
- [Usage](#usage)
- [Surviving a force stop](#surviving-a-force-stop)
- [Reference](#reference)
- [Known limits](#known-limits)
- [Example app](#example-app)
- [Debugging](#debugging)
- [Tests](#tests)
- [Documentation](#documentation)
- [License](#license)

## Why dozeless

Each usual option gives up something a job that runs every minute needs:

| | dozeless | WorkManager | Foreground service | `android_alarm_manager_plus` |
|---|:-:|:-:|:-:|:-:|
| Runs every minute | ✅ | ❌ periodic work runs at most every 15 minutes | – | ⚠️ `periodic` alarms are not exact |
| Keeps its schedule in Doze | ✅ | ❌ Doze defers it further | – | – |
| No notification while it runs | ✅ | – | ❌ on screen for as long as it runs | – |
| Waits for your callback | ✅ | – | – | ❌ does not wait |
| Holds the wake lock until the callback ends or times out | ✅ | – | – | ❌ released too early |
| When exact alarms are denied | ✅ falls back to inexact | – | – | ❌ skips silently |

– means this comparison makes no claim about that cell.

What dozeless asks in return: every job needs battery *Unrestricted* ([Prerequisites](#prerequisites)), a force stop still stops everything until a user action ([Surviving a force stop](#surviving-a-force-stop)), and the ✅ above rest on emulator tests ([Tested](#tested)). A first forced-Doze check on a HyperOS phone saw late alarms ([Known limits](#known-limits)).

## How it works

dozeless chains one-shot exact alarms (`setExactAndAllowWhileIdle`) per job. Every run goes like this:

1. The job's exact alarm fires, also in Doze.
2. dozeless arms the next alarm first, so a crash or a timeout never breaks the chain.
3. It takes a wake lock and calls your callback with a `JobContext` in a cached headless FlutterEngine, one run per job at a time.
4. It waits until the callback returns, throws or times out, records the status and releases the wake lock.

Around the chain, an hourly watchdog repairs lost or late alarms, and a receiver re-arms everything after boot, app update and clock changes. After a force stop, opening the app does it: see [Surviving a force stop](#surviving-a-force-stop).

## Tested

Emulator results (Pixel 9 / Pixel 5 profiles, battery set to *Unrestricted*). Each ✅ means the job kept writing rows to the example app's database in that state. – means not measured.

| Condition | 11 | 12 | 13 | 14 | 15 | 16 |
|---|:-:|:-:|:-:|:-:|:-:|:-:|
| App open | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| App in background | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Swiped away from Recents | ✅ | ✅ | ✅ | ✅ | ✅ | – |
| Process killed | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Screen off | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Doze (deep idle) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Reboot, app not opened | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Force stop, then app opened | ✅¹ | ✅¹ | ✅¹ | ✅¹ | ✅¹ | ✅¹ |

¹ Android blocks every alarm of a force-stopped app until the user brings it back. That holds for every app. dozeless recovers as soon as the app is opened and reports the stop as a `processExit` event (`USER_REQUESTED`). See [Surviving a force stop](#surviving-a-force-stop) for ways back that do not need the app to be opened.

**Real devices are still to be tested, starting with HyperOS.** So far there are only observations from one phone, not test results: see [Known limits](#known-limits) and [Force-stop guard](#force-stop-guard). What the emulator results cover:

- **Short checks.** Each ✅ on Android 11 to 15 is 1 or 2 runs per condition, 13 `spike` runs per version. The two Doze runs per version fired on time, except one 19 s late on Android 15.
- **Doze on Android 16.** Release build, screen off, unplugged, forced Doze for 7 minutes: `spike` ran 7 times (`idle=true`) with alarms 4 to 11 ms late, and the 20-second `slow` job finished twice.
- **Android 7 to 10** are not in the table, although `minSdk` is 24. Android 9 was tested partly: the job ran every minute, the other conditions were not tested.

Raw evidence for Android 11 to 15 (databases written by the jobs, logcat, per-condition logs) is in [`doc/test-results/`](https://github.com/xDaijobu/dozeless/tree/main/doc/test-results). The Android 16 column comes from earlier manual tests, so it has no per-condition log there; the later Android 16 probes are in [`doc/test-results/FORCE-STOP.md`](https://github.com/xDaijobu/dozeless/blob/main/doc/test-results/FORCE-STOP.md) (Indonesian).

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/xDaijobu/dozeless/main/doc/screenshots/doze-rows.png" width="250" alt="Rows written once a minute while the device was in Doze"></td>
  </tr>
  <tr>
    <td align="center"><sub>One row a minute while in Doze (<code>idle true</code>)</sub></td>
  </tr>
</table>

<sub>From the emulator test run (Android 16, Pixel 9), with the earlier UI of the example app.</sub>

## Features

- **Exact job chain** per job id (minimum interval 1 minute). Falls back to inexact alarms if exact alarms are denied.
- **Awaited Dart callback** with a timeout (≤ 50 s) and a partial wake lock. At most one run per job at a time.
- **Idempotent `schedule()`**: calling it on every app start never pushes the next run later.
- **Recovery** after reboot (`boot`), app update (`packageReplaced`), clock changes (`timeChanged`) and force stop. An hourly watchdog repairs lost or late chains.
- **Prerequisite gate.** When location, background location, battery *Unrestricted* or *not Restricted* go missing, the job stops, shows a notification and runs once with `prerequisiteLost`. Once fixed, it resumes with `resumed`.
- **Force-stop helpers** (opt-in): a Quick Settings tile that brings the app back without opening it, and a guard that disables Settings' "Force stop" button.
- **Rich `JobContext`**: trigger, how late the alarm fired, boot info, Doze, screen, standby bucket, ANDROID_ID, signal levels, and system events since the last run.

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
- `schedule()` limits, also enforced with an `ArgumentError`: `id` is 1 to 64 of `A-Z a-z 0-9 _ . -`, `every` is at least 1 minute, `timeout` is at most 50 s (default 45 s).
- dozeless does not request permissions. If a job `requires` location, the app must request it itself, for example with `permission_handler` as the [example app](#example-app) does. Otherwise the job stops at its first alarm, or sooner when the app starts or resumes.
- `stopNotification` sets the text of the notification shown when a job stops. The default is in English; apps can pass their own `title`, `body` and `channelName`.
- Other calls: `cancel(id)`, `status(id)`, `runNow(id)`, `checkPrerequisites()`, `openSettings(Setting)`, `disableForceStopGuard()`, and `debugFireIn`, `debugSimulateLostAlarm`, `debugRunWatchdog` for testing.

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
| `forceStopGuard` | never | `Setting.forceStopGuard` (system dialog), see below |

`checkPrerequisites()` reports `notBackgroundRestricted` inverted, as `backgroundRestricted`.

## Surviving a force stop

A force stop (App info → **Force stop**, and on some brands swiping the app away or the OEM cleaner) puts the app in Android's *stopped state*: every alarm is deleted and nothing of the app runs until a **user action** brings it back. No app can undo that by itself, and Android 15 closed the remaining gaps. dozeless gives you three ways that stay within those rules:

| | What happens | Verified | Setup |
|---|---|---|---|
| **Recovery on unstop** | Opening the app re-arms every job. On Android 15+, other user actions that end the stopped state do too, without opening the app: the system then sends `BOOT_COMPLETED`, and dozeless reconciles. On older versions those actions re-arm nothing, apart from the tile below (verified on Android 16 only). | Android 16 | none |
| **Quick Settings tile** | Pulling down Quick Settings while the tile is visible starts the app process in the background and re-arms every job. The app is not opened. | Android 16 | declare the service; the user adds the tile once |
| **Force-stop guard** | A device admin without policies. While it is active, Settings disables the app's **Force stop** button. | Android 16 | declare the receiver; the user activates it once |

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/xDaijobu/dozeless/main/doc/screenshots/quick-settings-tile.png" width="250" alt="Quick Settings with the Spike tile"></td>
    <td align="center"><img src="https://raw.githubusercontent.com/xDaijobu/dozeless/main/doc/screenshots/force-stop-disabled.png" width="250" alt="App info with Force stop disabled"></td>
  </tr>
  <tr>
    <td align="center"><sub>The optional tile in Quick Settings</sub></td>
    <td align="center"><sub>Force-stop guard on: <b>Force stop</b> is disabled</sub></td>
  </tr>
</table>

<sub>Android 16 emulator (Pixel 9).</sub>

"Verified" means checked on the Android 16 emulator, a few minutes per case. The planned one-hour runs per condition were cut short; what was measured, and how to rerun them, is in [`doc/test-results/FORCE-STOP.md`](https://github.com/xDaijobu/dozeless/blob/main/doc/test-results/FORCE-STOP.md) (Indonesian).

### Quick Settings tile

Declare the tile in your app's `AndroidManifest.xml` and give it an icon and a label:

```xml
<service
    android:name="io.github.xdaijobu.dozeless.DozelessTileService"
    android:exported="true"
    android:icon="@drawable/ic_tile"
    android:label="Tracking"
    android:permission="android.permission.BIND_QUICK_SETTINGS_TILE">
    <intent-filter>
        <action android:name="android.service.quicksettings.action.QS_TILE" />
    </intent-filter>
</service>
```

The user adds it once from the Quick Settings editor (pencil icon). From then on, every time Quick Settings opens with the tile on screen, and every time the tile is tapped, dozeless reconciles the jobs. The tile is active while every job runs, inactive when a job stopped for a missing prerequisite, and unavailable when no job is scheduled.

### Force-stop guard

Declare the receiver in your app's `AndroidManifest.xml`. The label and the description are what the system dialog shows:

```xml
<receiver
    android:name="io.github.xdaijobu.dozeless.DozelessAdminReceiver"
    android:description="@string/force_stop_guard_description"
    android:exported="true"
    android:label="@string/force_stop_guard_label"
    android:permission="android.permission.BIND_DEVICE_ADMIN">
    <meta-data
        android:name="android.app.device_admin"
        android:resource="@xml/dozeless_device_admin" />
    <intent-filter>
        <action android:name="android.app.action.DEVICE_ADMIN_ENABLED" />
    </intent-filter>
</receiver>
```

```dart
final p = await Dozeless.checkPrerequisites();
if (p.forceStopGuardAvailable && !p.forceStopGuard) {
  await Dozeless.openSettings(Setting.forceStopGuard); // system dialog, needs the app in the foreground
}
// later, for example on sign-out:
await Dozeless.disableForceStopGuard();
```

What to know before you use it:

- It only disables the **Force stop** button in Settings. `adb shell am force-stop`, task killers and OEM cleaners that force-stop apps directly are not affected.
- Android does not let the user uninstall an app with an active device admin. They have to turn it off first (Settings → Security → Device admin apps), or the app calls `disableForceStopGuard()`.
- The admin uses no policies (`res/xml/dozeless_device_admin.xml` in the plugin), so it cannot lock, wipe or watch the device. Google Play still reviews apps that declare a device admin; check its policy before you ship it in a store build.
- On HyperOS, the system's activation dialog is followed by a generic red **Danger** device-admin warning (erase all data, screen lock, camera; OK unlocks after 8 s), even though dozeless uses no policies. Tell users before they activate it. Observed on a POCO X6 Pro (HyperOS 3, Android 16) on 2026-11-04. That check was cancelled at this screen, so the guard itself has not been tried on a real device.
- If the app is the **device owner** (company-owned phones provisioned through an MDM or `dpm set-device-owner`), dozeless also calls `setUserControlDisabledPackages` on Android 11+, which blocks force stop and clear data on every Settings page. Not tested yet.

## Reference

### JobContext

| Field | Meaning |
|---|---|
| `jobId` | the id passed to `schedule()` |
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

- **Force stop** stops everything until a user action brings the app back (Android rule, see [Surviving a force stop](#surviving-a-force-stop)).
- **Xiaomi/HyperOS and other OEMs** may treat "swipe away" or their cleaner like a force stop, and may block `BOOT_COMPLETED` without Autostart. Ask users to enable Autostart and lock the app in Recents.
- **HyperOS may hold alarms in Doze** (an observation, not a test result). On a POCO X6 Pro (HyperOS 3, Android 16) on 2026-11-04, a short forced-Doze check through adb (screen on, simulated unplug) saw HyperOS freeze the app right after a run, and the next alarms ran about 4 minutes late, when Doze ended. This is not yet verified with a real screen-off run. Keep asking users for Autostart and battery *Unrestricted*, although both were already on in this check.
- **Location in the background can be stale.** Android 8+ gives background apps a fresh location only a few times per hour, so `getCurrentPosition` may return a cached fix with no error. Record the fix time and treat old fixes as stale.
- Runs of different jobs in one process are serialized by Android's broadcast queue. Keep timeouts short.

## Example app

[`example/`](https://github.com/xDaijobu/dozeless/tree/main/example) is the feasibility app used for every test above, since rebuilt with a new UI. `Dozeless Example` is an English Material 3 app with three tabs:

| Tab | What it shows |
|---|---|
| **Overview** | Job status hero (mode, next-run countdown, run count, last error), a card per job, Start/Stop, and a setup checklist of prerequisites with Fix buttons |
| **Runs** | Timeline of the last 24 h of runs with delay, duration, location and fix age, a Doze badge, standby bucket and system events |
| **Lab** | Statistics for the 30/90-minute screen-off test (expected, ran %, median delay, NOT YET / PASS / FAIL) and debug actions (run now, alarm in 10 s, simulate lost alarm, clear rows) |

Two jobs write a row to `spike.db` on every run: `spike` every minute (location, delay, Doze, screen, fix age) and `slow` every 5 minutes (awaits 20 seconds to prove the wake lock holds). The app declares both force-stop helpers; its Quick Settings tile is labelled `Spike`.

```bash
cd example
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example
```

Then open the app, tap **Start jobs** and fix the Setup checklist: the app schedules nothing by itself, and `spike` needs location "Allow all the time".

## Debugging

```bash
adb logcat -s Dozeless:I flutter:I
adb shell dumpsys alarm | grep -A4 "^ *tag=.*dozeless.RUN"       # one alarm per job
adb shell dumpsys alarm | grep -A4 "^ *tag=.*dozeless.WATCHDOG"  # hourly watchdog
adb shell dumpsys package <package> | grep -m1 stopped=           # stopped=true after a force stop
adb shell dumpsys deviceidle whitelist +<package>                 # battery Unrestricted, for tests
adb shell dumpsys deviceidle force-idle                           # force Doze (screen off, unplugged)
```

Job callbacks run in a separate engine, so hot reload does not reach them. Use hot restart or kill the app process after changing a job.

## Tests

```bash
flutter test                                  # Dart API, models, dispatcher
(cd example && flutter test)                  # example statistics and UI
(cd example && flutter build apk --config-only && cd android && ./gradlew :dozeless:testDebugUnitTest)   # Kotlin (JDK 17+)
(cd example && flutter test integration_test/dozeless_test.dart -d <device> --no-uninstall)
```

Integration tests need battery *Unrestricted* for the example app (`adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example`). `--no-uninstall` keeps that setting between runs.

## Documentation

[`doc/`](https://github.com/xDaijobu/dozeless/tree/main/doc) on GitHub is in Indonesian: test results per Android version (databases written by the jobs, logcat, the scripts that ran them) and the screenshots used in this README. It is not part of the pub.dev package.

## License

[Apache License 2.0](https://github.com/xDaijobu/dozeless/blob/main/LICENSE).
