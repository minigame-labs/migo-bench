#!/usr/bin/env bash
# Record one game on Migo and on the system WebView, one after the other on one device, with the numbers the
# harness measures sampled every second, for a side-by-side video (compose with compose-comparison.py).
#
#   record-comparison.sh --device SERIAL --game-asset NAME [--seconds 30] [--tap-every 0.9] [--out DIR]
#
# NAME is the game's asset directory in BOTH shells -- shells/migo-shell/app/src/main/assets/NAME (the game with the
# web adapter in front of it) and shells/webview-shell/app/src/main/assets/NAME (index.html + the same game) -- so the
# two arms run the same code, as every table in this repository does. The shells must already be installed.
#
# What is measured, per second, is what the rest of the harness measures, by the same means:
#   fps  frames actually presented in the last second: SurfaceFlinger's present timestamps for the game's layer
#        (Migo's SurfaceView; the WebView's window), so neither arm reports its own frame loop
#   pss  scripts/webview_pss.py over the system-wide meminfo: the app's process plus, for the WebView, its sandboxed
#        renderer -- the fair count RESULTS.md uses
# The screen is recorded with scrcpy (needs it on PATH). Taps go in at a fixed interval from the start of the recording, the same on both arms. The cold gate runs before
# each arm (lib.sh), and the gate line goes into the CSV next to the samples.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE=""; ASSET=""; SECS=30; TAP_EVERY=0.9; OUT="$DIR/../out/comparison"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEVICE="$2"; shift 2;; --game-asset) ASSET="$2"; shift 2;; --seconds) SECS="$2"; shift 2;;
    --tap-every) TAP_EVERY="$2"; shift 2;; --out) OUT="$2"; shift 2;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done
[[ -n "$DEVICE" && -n "$ASSET" ]] || { echo "usage: $0 --device SERIAL --game-asset NAME [--seconds N] [--tap-every S] [--out DIR]" >&2; exit 2; }
SERIAL="$DEVICE"
# shellcheck source=lib.sh
source "$DIR/lib.sh"   # ADB, require_one_device (screen kept on), cold_gate
require_one_device
mkdir -p "$OUT"
read -r W H < <("${ADB[@]}" shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1 | tr 'x' ' ')

layer_of() {  # <package> -> the SurfaceFlinger layer whose present times are the game's frames
  local list; list="$("${ADB[@]}" shell dumpsys SurfaceFlinger --list | tr -d '\r')"
  # grep -m1, not `| head -1`: under pipefail a reader that stops early kills the writer with SIGPIPE.
  local surface; surface="$(grep -F "SurfaceView[$1/" <<<"$list" | grep -F -m1 '(BLAST)' || true)"
  if [[ -n "$surface" ]]; then echo "$surface"; return 0; fi
  # A view-drawn window (the WebView's): its buffer layer is the one named after the activity alone; the one with a
  # token in front of it is the window's container and presents nothing.
  grep -E -m1 "^$1/" <<<"$list" || true
}

fps_now() {  # <layer> -> presents in the last second of SurfaceFlinger's 128-frame history
  "${ADB[@]}" shell "dumpsys SurfaceFlinger --latency '$1'" | tr -d '\r' | python3 -c '
import sys
t = [int(l.split()[1]) for l in sys.stdin.read().splitlines()[1:] if len(l.split()) == 3]
t = [x for x in t if 0 < x < 9 * 10**18]
print(len([x for x in t if t and t[-1] - x < 10**9]) if t else 0)'
}

record() {  # <runtime> <package> <activity> <extras...>
  local runtime="$1" pkg="$2" activity="$3"; shift 3
  "${ADB[@]}" shell am force-stop com.migo.bench.migo >/dev/null 2>&1 || true
  "${ADB[@]}" shell am force-stop com.migo.bench.webview >/dev/null 2>&1 || true
  local gate; gate="$(cold_gate "$runtime")"
  echo "[$runtime] gate: $gate" >&2
  "${ADB[@]}" shell am start -n "$pkg/$activity" "$@" >/dev/null
  sleep 5
  local layer; layer="$(layer_of "$pkg")"
  [[ -n "$layer" ]] || { echo "[$runtime] no layer for $pkg" >&2; return 1; }
  # scrcpy, not the device's screenrecord: HarmonyOS ships none, and scrcpy is the same on every device.
  rm -f "$OUT/$runtime.mp4"
  scrcpy -s "$DEVICE" --no-playback --no-audio --no-control --max-size 1280 --video-bit-rate 8M \
    --time-limit "$SECS" --record "$OUT/$runtime.mp4" > "$OUT/$runtime.scrcpy.log" 2>&1 &
  local rec=$! start; start=$(date +%s)
  ( while (( $(date +%s) - start < SECS )); do "${ADB[@]}" shell input tap $((W / 2)) $((H / 2)); sleep "$TAP_EVERY"; done ) &
  local taps=$!
  echo "second,fps,pss_kb,gate" > "$OUT/$runtime.csv"
  local second=0
  while (( second < SECS )); do
    local fps pss
    fps="$(fps_now "$layer")"
    # Read whole first: webview_pss.py stops at the section it needs, and a pipe from adb would then die of SIGPIPE.
    local meminfo; meminfo="$("${ADB[@]}" shell dumpsys meminfo 2>/dev/null | tr -d '\r')"
    pss="$(python3 "$DIR/webview_pss.py" "$pkg" <<<"$meminfo" | grep -o '[0-9]*' | tail -1)"
    second=$(( $(date +%s) - start ))
    echo "$second,$fps,$pss,\"$gate\"" >> "$OUT/$runtime.csv"
    sleep 1
  done
  wait "$rec" || true; kill "$taps" 2>/dev/null || true; wait "$taps" 2>/dev/null || true
  "${ADB[@]}" shell am force-stop "$pkg"
  echo "[$runtime] -> $OUT/$runtime.mp4, $OUT/$runtime.csv" >&2
}

record migo com.migo.bench.migo .BenchGameActivity --es migo_game_id bench --es migo_entry_point game.js --es game_asset "$ASSET"
record webview com.migo.bench.webview .WebViewBenchActivity --es game_asset "$ASSET"
{
  echo "device_model=$("${ADB[@]}" shell getprop ro.product.model | tr -d '\r')"
  echo "webview_version=$(adbsh dumpsys webviewupdate 2>/dev/null | awk -F': ' '/Current WebView package/{print $2}' | tr -d '\r')"
  echo "game_asset=$ASSET seconds=$SECS tap_every=$TAP_EVERY recorded=$(date -u +%FT%TZ)"
} > "$OUT/meta.txt"
echo "done -> $OUT" >&2
