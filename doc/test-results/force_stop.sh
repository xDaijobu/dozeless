#!/bin/bash
# Force-stop experiments, one hour per condition, against the example app on one emulator.
# usage: force_stop.sh <serial> <label> <outdir> [minutes per phase, default 60]
# The app must be installed (debug build), set up and running its jobs. Ground truth is spike.db.
set -u
S="$1"; L="$2"; OUT="$3"; MIN="${4:-60}"
PKG=io.github.xdaijobu.dozeless_example
TILE=$PKG/io.github.xdaijobu.dozeless.DozelessTileService
ADMIN=$PKG/io.github.xdaijobu.dozeless.DozelessAdminReceiver
SQLITE=/d/platform-tools/sqlite3.exe
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT"
LOG="$OUT/$L.log"; RES="$OUT/$L.result.md"; DB="$OUT/$L.db"
: > "$LOG"

A() { adb -s "$S" "$@"; }
log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }
alive() { # without this a dead emulator yields "0 runs" rows that look like results
  [ "$(adb -s "$S" get-state 2>/dev/null)" = device ] && return 0
  log "device $S hilang, berhenti (hasil setelah ini tidak ada)"; echo "FORCE_STOP_ABORTED $L"; exit 1
}
wait_phase() { local i; for i in $(seq "$MIN"); do sleep 60; alive; done; }
dev_ms() { echo $(( $(A shell date +%s | tr -d '\r') * 1000 )); }
pull_db() { A exec-out run-as $PKG cat databases/spike.db > "$DB" 2>/dev/null; }
q() { pull_db; "$SQLITE" "$(cygpath -w "$DB")" "$1" 2>/dev/null | tr -d '\r'; }
count_since() { local c; c=$(q "select count(*) from rows where jobId='spike' and firedAt > $1;"); echo "${c:-0}"; }
first_since() { q "select coalesce((min(firedAt) - $1) / 1000, '-') from rows where jobId='spike' and firedAt > $1;"; }
stopped() { A shell dumpsys package $PKG | grep -m1 -oE 'stopped=[a-z]+' | cut -d= -f2; }
alarms() { A shell dumpsys alarm | grep -cE '^ *tag=.*dozeless.RUN'; } # pending only; Android 16 also lists history lines "type=... tag=..."
pid() { A shell pidof $PKG 2>/dev/null | tr -d '\r'; }
state() { echo "proses=${1:-$(pid)} stopped=$(stopped) alarm=$(alarms)"; }
wake() { A shell input keyevent KEYCODE_WAKEUP; A shell wm dismiss-keyguard >/dev/null 2>&1; }
admin_active() { A shell dumpsys device_policy | grep -q "DozelessAdminReceiver" && echo on || echo off; }
tap_text() { # tap the element whose text or semantics label is exactly $1
  local i b
  for i in 1 2 3 4 5 6; do
    A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    b=$(A shell cat /sdcard/ui.xml | grep -oE "(text|content-desc)=\"$1\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | head -1 | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]')
    if [ -n "$b" ]; then
      set -- $(echo "$b" | tr '[],' '   ')
      A shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
      return 0
    fi
    sleep 3
  done
  return 1
}
has_text() { A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; A shell cat /sdcard/ui.xml | grep -q "text=\"$1\""; }
open_app() { wake; A shell am start -n $PKG/.MainActivity >/dev/null; sleep 8; }
admin_off() { # the app turns its own admin off ("Matikan pengaman" calls Dozeless.disableForceStopGuard)
  [ "$(admin_active)" = off ] && return 0
  open_app; tap_text "Matikan pengaman"; sleep 3
  A shell input keyevent KEYCODE_HOME
}
res() { # name expectation got note
  echo "| $1 | $2 | $3 | $4 |" >> "$RES"
  log "$1: $3 ($2) $4"
}

API=$(A shell getprop ro.build.version.sdk | tr -d '\r')
REL=$(A shell getprop ro.build.version.release | tr -d '\r')
{ echo "### Android $REL (API $API), $MIN menit per kondisi"; echo
  echo "| Kondisi | Harapan | Run spike | Catatan |"; echo "|---|---|---|---|"; } > "$RES"
alive; log "== $L: Android $REL API $API"
A logcat -v time -s Dozeless:I flutter:I AndroidRuntime:E >> "$OUT/$L.logcat" 2>/dev/null &
A shell cmd statusbar add-tile $TILE >/dev/null 2>&1
# Right after add-tile SystemUI is still bound to the tile, and a force stop then restarts the app within a second
# (seen on Android 14). Let it unbind first.
sleep 60

# 0. Android 15+ sends BOOT_COMPLETED when the app leaves the stopped state. Make the system wake the stopped app
#    with something that runs none of our job code (activating its device admin) and see if the chain comes back.
admin_off
A shell am force-stop $PKG; sleep 5
BEFORE=$(state)
A shell dpm set-active-admin --user current $ADMIN >/dev/null; sleep 15
AFTER=$(state)
UNSTOP=$(grep -c "no new boot" "$OUT/$L.logcat")
res "0. Force stop → app dibangunkan sistem (aktivasi device admin), tanpa dibuka" "API 35+: alarm kembali" "-" "sebelum: $BEFORE; sesudah 15 s: $AFTER; BOOT_COMPLETED tanpa reboot: ${UNSTOP}×"
admin_off

# 1. force stop, nothing else
A shell am force-stop $PKG; sleep 5
T=$(dev_ms); log "1. force stop, menunggu $MIN menit"
wait_phase
res "1. Force stop, tanpa interaksi apa pun" "0 (aturan Android)" "$(count_since "$T")" "admin=$(admin_active); $(state)"

# 2. the user only pulls down Quick Settings (the tile is visible); the app is not opened
wake; A shell cmd statusbar expand-settings; sleep 6; A shell cmd statusbar collapse
A shell input keyevent KEYCODE_HOME; A shell input keyevent KEYCODE_SLEEP
T=$(dev_ms); log "2. panel Quick Settings dibuka sekali, menunggu $MIN menit"
wait_phase
res "2. Force stop → panel Quick Settings dibuka (app tidak dibuka)" "~$MIN" "$(count_since "$T")" "run pertama +$(first_since "$T") s; $(state)"

# 3. force-stop guard on, the user presses Settings' Force stop
open_app; A shell input keyevent KEYCODE_HOME
A shell dpm set-active-admin --user current $ADMIN >/dev/null; sleep 2
wake; A shell am force-stop com.android.settings
A shell am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:$PKG >/dev/null; sleep 5
tap_text "Force stop"; sleep 2; DIALOG="tidak ada dialog konfirmasi"
if has_text "Force stop?"; then tap_text "OK"; DIALOG="dialog konfirmasi muncul, OK ditekan"; fi
sleep 2; AFTER_TAP=$(stopped)
A shell input keyevent KEYCODE_HOME; A shell input keyevent KEYCODE_SLEEP
T=$(dev_ms); log "3. pengaman aktif, Force stop ditekan ($DIALOG, stopped=$AFTER_TAP), menunggu $MIN menit"
wait_phase
res "3. Pengaman force stop aktif → tombol Force stop di Settings ditekan" "~$MIN" "$(count_since "$T")" "$DIALOG; stopped setelah tekan=$AFTER_TAP; admin=$(admin_active); $(state)"

# 3b. the guard does not cover adb or OEM cleaners that call forceStopPackage directly
A shell am force-stop $PKG; sleep 5
res "3b. Pengaman aktif → am force-stop (adb / pembersih OEM)" "tetap berhenti" "-" "$(state)"
wake; A shell cmd statusbar expand-settings; sleep 6; A shell cmd statusbar collapse

# 4. swiped away from Recents, then the screen goes off
open_app
SIZE=$(A shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1); W=${SIZE%x*}; H=${SIZE#*x}
A shell input keyevent KEYCODE_APP_SWITCH; sleep 4
A shell input swipe $((W / 2)) $((H / 2)) $((W / 2)) $((H / 12)) 300; sleep 4
A shell input keyevent KEYCODE_HOME; sleep 2; P=$(pid)
A shell input keyevent KEYCODE_SLEEP
T=$(dev_ms); log "4. swipe dari Recents + layar mati (pid setelah swipe: ${P:-mati}), menunggu $MIN menit"
wait_phase
res "4. Di-swipe dari Recents, lalu layar mati" "~$MIN" "$(count_since "$T")" "proses setelah swipe: ${P:-mati}; $(state)"

TOTAL=$(q "select count(*) from rows where jobId='spike';")
LATE=$(q "select coalesce(max(delayMs),0) from rows where jobId='spike' and trigger='alarm';")
{ echo; echo "Total run spike di database: $TOTAL · telat alarm terbesar: ${LATE} ms"; } >> "$RES"
log "SELESAI $L"
echo "FORCE_STOP_DONE $L"
