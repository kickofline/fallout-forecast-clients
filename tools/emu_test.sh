#!/usr/bin/env bash
# Build the test APK (armeabi-v7a + x86), install it on an API 22 x86
# EMULATOR, run the capture harness against a bridge (default: the mock on
# the host, ws://10.0.2.2:8790/), then pull screenshots + FPS log.
#
#   tools/emu_test.sh [OUT_DIR] [URL] [SECONDS]
#
# Needs: GODOT3 (Godot 3.6.3 binary), adb on PATH, ANDROID_HOME/JAVA_HOME,
# a running API 22 x86 emulator (EMU serial, default emulator-5554), and
# `python tools/mock_bridge.py --fast` on the host for the default URL.
set -euo pipefail
export MSYS_NO_PATHCONV=1
ROOT="$(cd "$(dirname "$0")/.." && (pwd -W 2>/dev/null || pwd))"
OUT="${1:-$ROOT/build/emu-captures}"
URL="${2:-ws://10.0.2.2:8790/}"
SECS="${3:-150}"
EMU="${EMU:-emulator-5554}"
GODOT3="${GODOT3:-C:/Users/drewd/Tools/Godot3/Godot_v3.6.3-stable_win64.exe}"
PKG=org.falloutforecast.car
A=(adb -s "$EMU")
APK="$ROOT/build/fallout-car-test.apk"
APP_FILES="/data/data/$PKG/files"
CAPTURE="capture-$(date +%s)-$$"

if [[ ! "$EMU" =~ ^emulator-[0-9]+$ ]]; then
	echo "Refusing non-emulator serial $EMU" >&2
	exit 2
fi
if [[ ! "$SECS" =~ ^[1-9][0-9]*$ ]]; then
	echo "Pass a positive integer results timeout in seconds" >&2
	exit 2
fi
if [[ ! "$URL" =~ ^wss?://[^[:space:]\']+$ ]]; then
	echo "Pass a ws:// or wss:// URL without spaces or single quotes" >&2
	exit 2
fi
adb devices -l
if [[ $("${A[@]}" shell getprop ro.build.version.sdk | tr -d '\r') != 22 ||
      $("${A[@]}" shell getprop ro.product.cpu.abi | tr -d '\r') != x86 ]]; then
	echo "$EMU must be a running API 22 x86 emulator" >&2
	exit 2
fi

mkdir -p "$OUT" "$ROOT/build"
python "$ROOT/tools/sync_assets.py"
rm -f "$APK"
if ! (cd "$ROOT/client" && "$GODOT3" --path . --no-window \
	--export-debug "Android Test" ../build/fallout-car-test.apk) > "$OUT/export.log" 2>&1 ||
	[[ ! -s "$APK" ]]; then
	tail -30 "$OUT/export.log" >&2
	echo "APK export failed. See $OUT/export.log" >&2
	exit 1
fi

"${A[@]}" root
for ((attempt = 0; attempt < 20; attempt++)); do
	if [[ $("${A[@]}" shell id 2>/dev/null | tr -d '\r') == uid=0\(* ]]; then
		break
	fi
	sleep 1
done
if ((attempt == 20)); then
	echo "$EMU did not restart its adb daemon as root" >&2
	exit 1
fi

"${A[@]}" install -r "$APK"
"${A[@]}" shell am force-stop "$PKG"
cleanup() {
	"${A[@]}" logcat -d -s 'godot:*' > "$OUT/logcat.txt" || true
	"${A[@]}" shell am force-stop "$PKG" || true
	"${A[@]}" shell "rm -f $APP_FILES/test_args.txt $APP_FILES/$CAPTURE/*.png $APP_FILES/$CAPTURE/fps.txt; rmdir $APP_FILES/$CAPTURE 2>/dev/null" || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"${A[@]}" shell "mkdir -p $APP_FILES; { echo '--url=$URL'; echo '--capture=user://$CAPTURE'; echo '--exit-when-done'; } > $APP_FILES/test_args.txt"
if [[ $("${A[@]}" shell cat "$APP_FILES/test_args.txt" | tr -d '\r' | head -1) != "--url=$URL" ]]; then
	echo "Failed to write Android capture arguments" >&2
	exit 1
fi
"${A[@]}" logcat -G 8M >/dev/null 2>&1 || true
"${A[@]}" logcat -c
"${A[@]}" shell am start -n "$PKG/com.godot.game.GodotApp"
echo "Waiting up to ${SECS}s for results"
deadline=$((SECONDS + SECS))
while ! "${A[@]}" logcat -d -s 'godot:*' | tr -d '\r' | grep -F "saved user://$CAPTURE/09-results.png" > /dev/null; do
	if ((SECONDS >= deadline)); then
		echo "Results timed out. See $OUT/logcat.txt" >&2
		exit 1
	fi
	sleep 2
done
for f in $("${A[@]}" shell "ls $APP_FILES/$CAPTURE/*.png" | tr -d '\r'); do
	"${A[@]}" pull "$f" "$OUT/${f##*/}" >/dev/null
done
"${A[@]}" pull "$APP_FILES/$CAPTURE/fps.txt" "$OUT/fps.txt" >/dev/null
test -s "$OUT/09-results.png"
test -s "$OUT/fps.txt"
"${A[@]}" logcat -d -s 'godot:*' > "$OUT/logcat.txt"
grep -E "PERF|CAPTURE|ERROR" "$OUT/logcat.txt" | tail -40 || true
ls "$OUT"
