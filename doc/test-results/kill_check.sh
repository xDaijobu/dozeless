#!/bin/bash
# Re-runs only condition 4 (process killed) on the Android 13 AVD, with the run-as -> am kill fallback.
SP=/c/Users/UseR/AppData/Local/Temp/claude/D--Cris-MSN-Github-Xamarin-sato/ed8048bf-6ca7-4885-b3ff-df23da940387/scratchpad
EMU=/c/Users/UseR/AppData/Local/Android/sdk/emulator/emulator.exe
OUT=$SP/matrix_out; LOG=$OUT/api33-kill.log; DB=$OUT/api33-kill.db
PKG=com.example.bg_jobs_example; SQLITE=/d/platform-tools/sqlite3.exe
export MSYS_NO_PATHCONV=1
: > "$LOG"
log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }
count_since() { adb exec-out run-as $PKG cat databases/spike.db > "$DB" 2>/dev/null; local c; c=$("$SQLITE" "$(cygpath -w "$DB")" "select count(*) from rows where jobId='spike' and firedAt > $1;" 2>/dev/null | tr -d '\r'); echo "${c:-0}"; }
wait_rows() { local start c; start=$(date +%s); while :; do c=$(count_since "$1"); [ "$c" -ge "$2" ] && break; [ $(( $(date +%s) - start )) -ge "$3" ] && break; sleep 10; done; echo "$c"; }
pid() { adb shell pidof $PKG 2>/dev/null | tr -d '\r'; }
dev_ms() { echo $(( $(adb shell date +%s | tr -d '\r') * 1000 )); }

"$EMU" -avd bgjobs_api33 -memory 4096 -no-snapshot -no-boot-anim -no-window -no-audio > "$SP/emu_api33b.log" 2>&1 &
adb wait-for-device
for _ in $(seq 1 300); do [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 2; done
sleep 30
log "booted Android $(adb shell getprop ro.build.version.release | tr -d '\r')"
adb shell dumpsys deviceidle whitelist +$PKG >/dev/null
adb shell input keyevent KEYCODE_WAKEUP; adb shell wm dismiss-keyguard >/dev/null 2>&1
adb shell am start -n $PKG/.MainActivity >/dev/null
T=$(dev_ms); C=$(wait_rows "$T" 1 150); log "sebelum kill: $C run (jadwal masih ada setelah reboot + app dibuka)"
adb shell input keyevent KEYCODE_HOME; sleep 3
P=$(pid); HOW="kill -9"
[ -n "$P" ] && adb shell run-as $PKG kill -9 "$P"
sleep 2; P2=$(pid)
if [ -n "$P2" ] && [ "$P2" = "$P" ]; then adb shell am kill $PKG; sleep 2; P2=$(pid); HOW="am kill"; fi
T=$(dev_ms); C=$(wait_rows "$T" 2 200)
OK="❌"; [ "$C" -ge 2 ] && [ "$P2" != "$P" ] && OK="✅"
log "4. Proses dibunuh (ulang): $OK $C/2 pid ${P:-?} -> ${P2:-mati} ($HOW)"
adb emu kill >/dev/null 2>&1
log "KILL_CHECK_DONE"
