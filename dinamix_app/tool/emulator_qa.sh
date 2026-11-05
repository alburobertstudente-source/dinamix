#!/usr/bin/env bash
# QA on an Android emulator (report §18): integration test of the real app,
# then lifecycle, stress and log checks on the release APK.
# Usage (from dinamix_app/): bash tool/emulator_qa.sh <path/to/dinamix.apk>
set -u
APK="${1:-../apk/dinamix.apk}"
PKG=com.dinamix.dinamix
OUT=qa
mkdir -p "$OUT"
status=0
step() { echo "== $*" | tee -a "$OUT/summary.txt"; }

adb shell getprop ro.build.version.release | sed 's/^/Android /' | tee -a "$OUT/summary.txt"
adb shell getprop ro.product.model | sed 's/^/Modello /' | tee -a "$OUT/summary.txt"
adb logcat -c

step "Test d'integrazione (build di debug)"
flutter test integration_test/app_flow_test.dart -d emulator-5554 2>&1 | tee "$OUT/integration.txt"
it=${PIPESTATUS[0]}
echo "esito integrazione: $it" | tee -a "$OUT/summary.txt"
[ "$it" -ne 0 ] && status=1
adb logcat -d > "$OUT/logcat_integration.txt"
adb uninstall "$PKG" >/dev/null 2>&1 || true

step "Installazione APK di release"
adb install -r "$APK" 2>&1 | tee -a "$OUT/summary.txt" || status=1
adb logcat -c
sha256sum "$APK" | tee -a "$OUT/summary.txt"

step "Avvio a freddo"
adb shell am start -W -n "$PKG/.MainActivity" | tee "$OUT/start_cold.txt"
grep -E "TotalTime|WaitTime" "$OUT/start_cold.txt" | tee -a "$OUT/summary.txt"
sleep 6

step "Rotazione dello schermo"
adb shell settings put system accelerometer_rotation 0
adb shell settings put system user_rotation 1; sleep 3
adb shell settings put system user_rotation 0; sleep 3

step "Background e ripresa"
adb shell input keyevent KEYCODE_HOME; sleep 4
adb shell am start -W -n "$PKG/.MainActivity" | grep -E "TotalTime" | sed 's/^/ripresa: /' | tee -a "$OUT/summary.txt"
sleep 3

step "Processo terminato in background e riapertura"
adb shell input keyevent KEYCODE_HOME; sleep 2
adb shell am kill "$PKG"; sleep 2
adb shell am start -W -n "$PKG/.MainActivity" | grep -E "TotalTime" | sed 's/^/dopo kill: /' | tee -a "$OUT/summary.txt"
sleep 4

step "Permesso notifiche revocato durante l'uso"
adb shell pm revoke "$PKG" android.permission.POST_NOTIFICATIONS 2>/dev/null || true
sleep 2
adb shell am start -W -n "$PKG/.MainActivity" >/dev/null; sleep 3

step "Stress: 800 eventi casuali (monkey, seme 42)"
adb shell monkey -p "$PKG" --pct-syskeys 0 --pct-appswitch 5 -s 42 --throttle 60 800 2>&1 | tail -5 | tee -a "$OUT/summary.txt"
sleep 3

step "Memoria e fotogrammi"
adb shell dumpsys meminfo "$PKG" > "$OUT/meminfo.txt"
grep -E "TOTAL PSS|TOTAL RSS|TOTAL:" "$OUT/meminfo.txt" | head -3 | tee -a "$OUT/summary.txt"
adb shell dumpsys gfxinfo "$PKG" > "$OUT/gfxinfo.txt"
grep -E "Total frames rendered|Janky frames|50th percentile|90th percentile|99th percentile" "$OUT/gfxinfo.txt" | head -6 | tee -a "$OUT/summary.txt"

adb logcat -d > "$OUT/logcat_release.txt"
step "Controllo crash nei log"
if grep -E "FATAL EXCEPTION|ANR in $PKG|E/flutter.*Unhandled" "$OUT/logcat_release.txt" "$OUT/logcat_integration.txt" > "$OUT/crashes.txt"; then
  echo "CRASH O ANR TROVATI:" | tee -a "$OUT/summary.txt"
  head -40 "$OUT/crashes.txt" | tee -a "$OUT/summary.txt"
  status=1
else
  echo "nessun FATAL EXCEPTION, ANR o eccezione Dart non gestita" | tee -a "$OUT/summary.txt"
fi
exit $status
