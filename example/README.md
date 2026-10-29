# dozeless_example

Feasibility app for `dozeless` (spec §9). Two jobs write a row to `spike.db` on every run:

- `spike` every minute: takes a location with `geolocator`, records how late the alarm fired, Doze, screen and fix age.
- `slow` every 5 minutes: awaits 20 seconds, to prove the wake lock holds.

The screen shows the prerequisites with buttons to fix them, job status, statistics for the 90-minute screen-off test and the latest rows.

```bash
flutter test                                    # statistics unit tests
flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example
flutter test integration_test/dozeless_test.dart -d <device> --no-uninstall
```
