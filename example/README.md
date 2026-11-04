# Dozeless Example

The example app for [`dozeless`](../README.md), and the feasibility rig behind every result in
[`doc/test-results/`](../doc/test-results/). It schedules two jobs that write a row to `spike.db` on every run:

- `spike`, every minute: takes a location fix with `geolocator` and records how late the alarm fired, whether the
  phone was in Doze, the screen state, the standby bucket and how old the fix was.
- `slow`, every 5 minutes: holds the wake lock for 20 seconds, to prove the run is not cut short.

## What's in the app

The app has three tabs. It refreshes when it comes back to the foreground, every 10 seconds, and when you pull down.

**Overview** shows whether the jobs are running, in `exact`, `inexact` or `stopped` mode (`mixed` when the two jobs
differ), with a live countdown to the next run, the run count and the last error. `schedule()` doesn't check
prerequisites, so a job started without one stops at its first alarm, or when the app next comes to the foreground;
the Overview says so ahead of time ("Setup needed") instead of looking healthy. Below that is one card per job and the setup checklist: every
prerequisite with its status, why it matters and a Fix button that opens the right permission dialog or settings
page (location, location all the time, battery optimization, background usage, exact alarms, notifications,
Autostart on brands that have it, and the force-stop guard).

**Runs** is a timeline of the last 24 hours, newest first: when each run fired, which job, its trigger
(`alarm`, `watchdog`, `boot`, `manual`, ...), how late it was, how long it took, the location result and fix age, a
Doze badge when the phone was idle, the standby bucket and the system events dozeless saw. Runs 10 seconds late or
more, and fixes older than two intervals, are marked in the warning color: the same bars the screen-off test uses.

**Lab** holds the screen-off test and the debug actions:

- Screen-off test: start the jobs, turn the screen off and leave the phone alone, then check the numbers for the last
  30 or 90 minutes. Counting starts at the first `spike` alarm run, and the verdict reads NOT YET, with the minutes
  collected so far, until the runs cover the whole window. Then it is PASS or FAIL: PASS needs at least 95% of the
  expected `spike` runs, a median delay under 10 seconds and a location on every run.
- Run now, Alarm in 10 s and Simulate lost alarm (drops the alarm, then runs the watchdog that repairs it) act on
  `spike`, so they work while `spike` is scheduled and not stopped. Run now waits for a run that is already going.
  Clear rows works any time, and Turn off force-stop guard while the guard is on.
- Shortcuts to the settings pages, so you can undo a fix and watch dozeless stop the jobs and resume them when you
  come back to the app. Exact alarms and Autostart are different: without exact alarms the jobs keep running on
  inexact alarms, and turning Autostart off never stops them, because dozeless can't read it (it only matters after a
  reboot).

The manifest declares both optional force-stop helpers: the Quick Settings tile (`DozelessTileService`, label
"Spike") and the force-stop guard (`DozelessAdminReceiver`).

## Code

- `lib/main.dart` initializes dozeless and connects the screens to the plugins (`PluginBackend`).
- `lib/spike_jobs.dart`, `spike_db.dart`, `spike_row.dart` and `spike_stats.dart` are the jobs, the database and the
  pass/fail statistics.
- `lib/ui/` holds the screens. They take plain data (`PrerequisiteStatus`, `JobStatus`, `SpikeRow`, `SpikeStats`)
  and callbacks, so the widget tests in `test/` run without a device.

## Run it

```bash
flutter test                                    # statistics and widget tests
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example
flutter test integration_test/dozeless_test.dart -d <device> --no-uninstall
```

The integration tests need battery *Unrestricted* for the app; the `deviceidle whitelist` line sets it, and
`--no-uninstall` keeps it between runs.
