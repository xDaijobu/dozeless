#!/bin/bash
# Runs matrix.sh on one emulator per API level, one at a time.
# usage: run_all.sh 34 35 33 ...
SP=${SP:-./scratch}
APK="$SP/bg_jobs/example/build/app/outputs/flutter-apk/app-debug.apk"
EMU=${EMU:-emulator}
OUT=$SP/matrix_out
PROGRESS=$OUT/progress.log
mkdir -p "$OUT"

stop_emulator() {
  adb devices | grep -q emulator && adb emu kill >/dev/null 2>&1
  for _ in $(seq 1 60); do adb devices | grep -q emulator || return 0; sleep 2; done
}

for v in "$@"; do
  stop_emulator
  MEM=4096; [ "$v" -le 30 ] && MEM=3072
  echo "[$(date +%T)] api$v: start emulator (${MEM} MB)" >> "$PROGRESS"
  "$EMU" -avd "bgjobs_api$v" -memory $MEM -no-snapshot -no-boot-anim -no-window -no-audio > "$SP/emu_api$v.log" 2>&1 &
  timeout 600 adb wait-for-device
  booted=0
  for _ in $(seq 1 300); do [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '')" = "1" ] && { booted=1; break; }; sleep 2; done
  if [ "$booted" != 1 ]; then
    echo "[$(date +%T)] api$v: BOOT TIMEOUT" >> "$PROGRESS"; continue
  fi
  sleep 30  # let the post-boot burst of system services settle
  echo "[$(date +%T)] api$v: booted, running matrix" >> "$PROGRESS"
  bash "$SP/matrix.sh" emulator-5554 "api$v" "$APK" "$OUT" > "$OUT/api$v.stdout" 2>&1
  echo "[$(date +%T)] api$v: matrix finished" >> "$PROGRESS"
done
stop_emulator
echo "[$(date +%T)] ALL_DONE" >> "$PROGRESS"
