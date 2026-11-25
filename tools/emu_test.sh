#!/usr/bin/env bash
# Build the test APK (armeabi-v7a + x86), install it on an API 22 x86
# EMULATOR, run the capture harness against a bridge (default: the mock on
# the host, ws://10.0.2.2:8790/), then pull screenshots + FPS log.
#
#   tools/emu_test.sh [OUT_DIR] [URL] [SECONDS]
#
# Needs: GODOT3 (Godot 3.6.3 binary), ANDROID_HOME/JAVA_HOME (adb, apksigner),
# a running emulator (EMU serial, default emulator-5554) and, for the default
# URL, `python tools/mock_bridge.py --fast` on the host. Only ever targets the
# emulator serial; never a physical device.
set -euo pipefail
export MSYS_NO_PATHCONV=1
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
OUT="${1:-$ROOT/build/emu-captures}"
URL="${2:-ws://10.0.2.2:8790/}"
SECS="${3:-150}"
EMU="${EMU:-emulator-5554}"
GODOT3="${GODOT3:-C:/Users/drewd/Tools/Godot3/Godot_v3.6.3-stable_win64.exe}"
PKG=org.falloutforecast.car
A="adb -s $EMU"

case "$EMU" in emulator-*) ;; *) echo "refusing non-emulator serial $EMU"; exit 2;; esac

python "$ROOT/tools/sync_assets.py"
(cd "$ROOT/client" && "$GODOT3" --path . --no-window --export-debug "Android Test" ../build/fallout-car-test.apk 2>&1 | grep -E "ERROR|export: end" || true)
$A root >/dev/null 2>&1 || true
sleep 2
$A install -r "$ROOT/build/fallout-car-test.apk" | tail -1
$A shell am force-stop $PKG
$A shell "rm -rf /data/data/$PKG/files/captures; mkdir -p /data/data/$PKG/files"
$A shell "echo '--url=$URL' > /data/data/$PKG/files/test_args.txt; echo '--capture=user://captures' >> /data/data/$PKG/files/test_args.txt"
$A logcat -G 8M >/dev/null 2>&1 || true
$A logcat -c
$A shell am start -n $PKG/com.godot.game.GodotApp >/dev/null
echo "running for ${SECS}s..."
sleep "$SECS"
mkdir -p "$OUT"
$A logcat -d -s godot:* > "$OUT/logcat.txt" || true
for f in $($A shell "ls /data/data/$PKG/files/captures" | tr -d '\r'); do
	$A pull "/data/data/$PKG/files/captures/$f" "$OUT/$f" >/dev/null
done
# Leave the next launch clean (no capture harness).
$A shell "rm -f /data/data/$PKG/files/test_args.txt"
grep -E "PERF|CAPTURE|ERROR" "$OUT/logcat.txt" | tail -40 || true
ls "$OUT"
