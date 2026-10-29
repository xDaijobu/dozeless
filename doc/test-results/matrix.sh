#!/bin/bash
# Runs every app-state condition against the bg_jobs example on one emulator.
# usage: matrix.sh <serial> <label> <apk (Windows path)> <outdir>
# Ground truth is the example's spike.db (rows written by the background job), not logcat.
set -u
S="$1"; L="$2"; APK="$3"; OUT="$4"
PKG=com.example.bg_jobs_example
SQLITE=/d/platform-tools/sqlite3.exe
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT"
LOG="$OUT/$L.log"; RES="$OUT/$L.result.md"; DB="$OUT/$L.db"
: > "$LOG"

A() { adb -s "$S" "$@"; }
log() { echo "[$(date +%T)] $*" | tee -a "$LOG"; }
dev_ms() { echo $(( $(A shell date +%s | tr -d '\r') * 1000 )); }
pull_db() { A exec-out run-as $PKG cat databases/spike.db > "$DB" 2>/dev/null; }
q() { pull_db; "$SQLITE" "$(cygpath -w "$DB")" "$1" 2>/dev/null | tr -d '\r'; }
count_since() { local c; c=$(q "select count(*) from rows where jobId='spike' and firedAt > $1;"); echo "${c:-0}"; }
detail_since() {
  q "select group_concat(trigger || '(' || (delayMs/1000) || 's' || case when deviceIdle=1 then ',idle' else '' end || case when interactive=0 then ',layar-mati' else '' end || ')', ' ') from (select * from rows where jobId='spike' and firedAt > $1 order by firedAt);"
}
wait_rows() { # t0 n timeoutSec -> echoes count
  local t0=$1 n=$2 to=$3 start c
  start=$(date +%s)
  while :; do
    c=$(count_since "$t0")
    [ "$c" -ge "$n" ] && break
    [ $(( $(date +%s) - start )) -ge "$to" ] && break
    sleep 10
  done
  echo "$c"
}
res() { # name expected got note
  local ok="❌"
  [ "$3" -ge "$2" ] && ok="✅"
  echo "| $1 | $ok | $3/$2 | $4 |" >> "$RES"
  log "$1: $ok $3/$2 $4"
}
wake() { A shell input keyevent KEYCODE_WAKEUP; A shell wm dismiss-keyguard >/dev/null 2>&1; A shell input keyevent 82; }
pid() { A shell pidof $PKG 2>/dev/null | tr -d '\r'; }
start_logcat() { A logcat -v time -s BgJobs:V flutter:I AndroidRuntime:E >> "$OUT/$L.logcat" 2>/dev/null & }
tap_desc() { # tap the Flutter widget whose semantics label is $1
  local want="$1" i b
  for i in 1 2 3 4 5 6 7 8; do
    A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1
    b=$(A shell cat /sdcard/ui.xml | grep -oE "content-desc=\"$want\"[^>]*bounds=\"\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]\"" | head -1 | grep -oE '\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]')
    if [ -n "$b" ]; then
      set -- $(echo "$b" | tr '[],' '   ')
      A shell input tap $(( ($1 + $3) / 2 )) $(( ($2 + $4) / 2 ))
      return 0
    fi
    sleep 5
  done
  return 1
}

API=$(A shell getprop ro.build.version.sdk | tr -d '\r')
REL=$(A shell getprop ro.build.version.release | tr -d '\r')
{ echo "### Android $REL (API $API)"; echo; echo "| Kondisi | Jalan? | Run | Catatan |"; echo "|---|---|---|---|"; } > "$RES"
log "== $L: Android $REL API $API"

# --- setup: clean install, permissions, battery unrestricted, location
A uninstall $PKG >/dev/null 2>&1
log "install: $(A install -r "$APK" 2>&1 | tail -1 | tr -d '\r')"
A shell pm grant $PKG android.permission.ACCESS_FINE_LOCATION
A shell pm grant $PKG android.permission.ACCESS_COARSE_LOCATION
[ "$API" -ge 29 ] && A shell pm grant $PKG android.permission.ACCESS_BACKGROUND_LOCATION
[ "$API" -ge 33 ] && A shell pm grant $PKG android.permission.POST_NOTIFICATIONS
A shell dumpsys deviceidle whitelist +$PKG >/dev/null
A shell settings put system screen_off_timeout 1800000
A shell svc power stayon false
A emu geo fix 106.8456 -6.2088 >/dev/null
start_logcat
wake
A shell am start -n $PKG/.MainActivity >/dev/null
sleep 15
if ! tap_desc "Start"; then log "GAGAL menemukan tombol Start"; echo "| Setup | ❌ | - | tombol Start tidak ketemu |" >> "$RES"; exit 1; fi
log "Start ditekan"
sleep 3
PRE=$(q "select mode from rows limit 1;")

# 1. app open in the foreground
T=$(dev_ms); C=$(wait_rows "$T" 2 200); res "1. App terbuka (foreground)" 2 "$C" "$(detail_since "$T")"

# 2. app in the background (Home)
A shell input keyevent KEYCODE_HOME
T=$(dev_ms); C=$(wait_rows "$T" 1 130); res "2. App di background (Home)" 1 "$C" "$(detail_since "$T")"

# 3. swiped away from Recents
wake; A shell am start -n $PKG/.MainActivity >/dev/null; sleep 6
SIZE=$(A shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -1); W=${SIZE%x*}; H=${SIZE#*x}
A shell input keyevent KEYCODE_APP_SWITCH; sleep 4
if [ "$API" -ge 28 ]; then
  A shell input swipe $((W / 2)) $((H / 2)) $((W / 2)) $((H / 12)) 300
else
  A shell input swipe $((W / 2)) $((H * 6 / 10)) $((W - 10)) $((H * 6 / 10)) 300
fi
sleep 4; A shell input keyevent KEYCODE_HOME; sleep 2
P=$(pid); NOTE3="proses mati setelah swipe"; [ -n "$P" ] && NOTE3="PERHATIAN: proses masih hidup (pid $P), swipe mungkin tidak kena"
T=$(dev_ms); C=$(wait_rows "$T" 2 200); res "3. Di-swipe dari Recents" 2 "$C" "$NOTE3; $(detail_since "$T")"

# 4. process killed (like the low-memory killer); fall back to "am kill" if run-as cannot signal it
A shell input keyevent KEYCODE_HOME; sleep 3
P=$(pid); HOW="kill -9"
[ -n "$P" ] && A shell run-as $PKG kill -9 "$P"
sleep 2; P2=$(pid)
if [ -n "$P2" ] && [ "$P2" = "$P" ]; then A shell am kill $PKG; sleep 2; P2=$(pid); HOW="am kill"; fi
KILLED="pid ${P:-?} -> ${P2:-mati} ($HOW)"; [ -n "$P2" ] && [ "$P2" = "$P" ] && KILLED="PERHATIAN: proses tidak berhasil dibunuh (pid $P)"
T=$(dev_ms); C=$(wait_rows "$T" 2 200); res "4. Proses dibunuh" 2 "$C" "$KILLED; $(detail_since "$T")"

# 5. screen off
A shell input keyevent KEYCODE_SLEEP; sleep 3
T=$(dev_ms); C=$(wait_rows "$T" 1 130); res "5. Layar mati" 1 "$C" "$(detail_since "$T")"

# 6. Doze (deep idle forced, unplugged)
A shell dumpsys battery unplug
A shell dumpsys deviceidle force-idle >/dev/null
DEEP=$(A shell dumpsys deviceidle get deep | tr -d '\r')
T=$(dev_ms); C=$(wait_rows "$T" 2 200)
IDLE=$(q "select count(*) from rows where jobId='spike' and firedAt > $T and deviceIdle=1;")
res "6. Doze (deep $DEEP)" 2 "$C" "idle=true di ${IDLE:-0} run; $(detail_since "$T")"
A shell dumpsys deviceidle unforce >/dev/null; A shell dumpsys battery reset

# 7. reboot without opening the app
T=$(dev_ms)
A reboot; sleep 5; A wait-for-device
A shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'
start_logcat
A emu geo fix 106.8456 -6.2088 >/dev/null
C=$(wait_rows "$T" 2 300)
BOOT=$(q "select count(*) from rows where jobId='spike' and firedAt > $T and trigger='boot';")
res "7. HP reboot (app tidak dibuka)" 2 "$C" "run trigger=boot: ${BOOT:-0}; $(detail_since "$T")"

# 8. force stop: Android blocks every alarm until the user opens the app again
A shell am force-stop $PKG
T=$(dev_ms); C=$(wait_rows "$T" 1 130)
if [ "$C" -eq 0 ]; then FS="berhenti (aturan Android untuk force stop)"; else FS="masih jalan $C run"; fi
wake; A shell am start -n $PKG/.MainActivity >/dev/null
T2=$(dev_ms); C2=$(wait_rows "$T2" 1 150)
EXITEV=$(q "select count(*) from rows where firedAt > $T2 and events like '%processExit%';")
res "8. Force stop → app dibuka lagi" 1 "$C2" "selama force stop: $FS; setelah dibuka: pulih, event processExit di ${EXITEV:-0} run; $(detail_since "$T2")"

SLOW=$(q "select count(*) || ' run, terpendek ' || coalesce(min(finishedAt-startedAt)/1000,0) || ' s' from rows where jobId='slow';")
LOCS=$(q "select locationStatus || '=' || count(*) from rows where jobId='spike' group by locationStatus;" | tr '\n' ' ')
MODES=$(q "select mode || '=' || count(*) from rows group by mode;" | tr '\n' ' ')
TOTAL=$(q "select count(*) from rows where jobId='spike';")
{ echo; echo "Job 20 detik (slow): $SLOW · mode alarm: $MODES · lokasi: $LOCS · total run spike: $TOTAL"; } >> "$RES"
log "SELESAI $L"
echo "MATRIX_DONE $L"
