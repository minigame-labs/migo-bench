#!/usr/bin/env bash
# Shared helpers for the migo-bench harness: adb wiring, provenance, and the
# layered (system-level -> game-telemetry) fps capture.
set -euo pipefail

HARNESS_VERSION="1.0.0"
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ADB_BIN="${ADB_BIN:-/home/xg/Android/Sdk/platform-tools/adb}"
SERIAL="${SERIAL:-}"
ADB=("$ADB_BIN"); [[ -n "$SERIAL" ]] && ADB=("$ADB_BIN" -s "$SERIAL")

require_one_device() {
  command -v "$ADB_BIN" >/dev/null 2>&1 || { echo "ERROR: adb not found at $ADB_BIN" >&2; exit 2; }
  if [[ -z "$SERIAL" ]]; then
    local n; n=$("${ADB[@]}" devices | grep -cw device || true)
    [[ "$n" -eq 1 ]] || { echo "ERROR: need exactly 1 device or SERIAL=; found $n" >&2; "${ADB[@]}" devices >&2; exit 2; }
  fi
}

adbsh() { "${ADB[@]}" shell "$@"; }

# provenance_kv <pkg>  -> key=value lines (migo_version filled by the caller)
provenance_kv() {
  echo "device_model=$(adbsh getprop ro.product.model | tr -d '\r')"
  echo "device_brand=$(adbsh getprop ro.product.brand | tr -d '\r')"
  echo "android_release=$(adbsh getprop ro.build.version.release | tr -d '\r')"
  echo "android_sdk=$(adbsh getprop ro.build.version.sdk | tr -d '\r')"
  echo "abi=$(adbsh getprop ro.product.cpu.abi | tr -d '\r')"
  echo "webview_version=$(adbsh dumpsys webviewupdate 2>/dev/null | awk -F': ' '/Current WebView package/{print $2}' | tr -d '\r')"
  echo "harness_version=$HARNESS_VERSION"
  echo "timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "app_version=$(adbsh dumpsys package "$1" 2>/dev/null | awk -F= '/versionName/{print $2; exit}' | tr -d ' \r')"
}

# capture_fps <pkg> <duration_sec> <out_prefix>
#   writes <out_prefix>_fps.txt (one fps value per line) and echoes "fps_source=<surfaceflinger|game-telemetry>".
#   Primary: SurfaceFlinger --latency present-timestamps (app-agnostic). Fallback (EMUI, all-zeros):
#   the game's own `fps=N` telemetry for BOTH runtimes (symmetric). See spec section 2.
capture_fps() {
  local pkg="$1" dur="$2" pfx="$3"
  "${ADB[@]}" shell dumpsys SurfaceFlinger --latency-clear >/dev/null 2>&1 || true
  "${ADB[@]}" logcat -c >/dev/null 2>&1 || true
  sleep "$dur"

  # 1) SurfaceFlinger: pick the app layer with the most non-zero present rows.
  local layers best_raw="" best_n=0 L raw n
  layers=$("${ADB[@]}" shell dumpsys SurfaceFlinger --list 2>/dev/null | tr -d '\r' | grep -F "$pkg" || true)
  while IFS= read -r L; do
    [ -z "$L" ] && continue
    raw=$("${ADB[@]}" shell dumpsys SurfaceFlinger --latency "'$L'" 2>/dev/null || true)
    n=$(printf '%s\n' "$raw" | awk 'NR>1 && $2+0>0 && $2+0<9.2e18{c++} END{print c+0}')
    if [ "${n:-0}" -gt "$best_n" ]; then best_n="$n"; best_raw="$raw"; fi
  done <<< "$layers"

  if [ "$best_n" -ge 10 ]; then
    printf '%s\n' "$best_raw" | python3 "$LIB_DIR/sf_fps.py" > "${pfx}_fps.txt"
    echo "fps_source=surfaceflinger"
    return 0
  fi

  # 2) Fallback: game telemetry (symmetric, both runtimes run the same game fps counter).
  "${ADB[@]}" logcat -d 2>/dev/null | grep -oE 'fps=[0-9]+' | sed 's/fps=//' > "${pfx}_fps.txt" || true
  echo "fps_source=game-telemetry"
}

# capture_mem <pkg> <out_file>  -> dumpsys meminfo
capture_mem() { "${ADB[@]}" shell dumpsys meminfo "$1" > "$2" 2>/dev/null || true; }

# cold_start_ms <pkg> <launch_activity> <displayed_activity> <runs>
#   Cold launches <runs> times; each reads ActivityManager's system-level
#   "Displayed <pkg>/<displayed_activity>: +Nms" (launch -> first surface frame).
#   For migo, launch=.LauncherActivity but the displayed activity is .BenchGameActivity
#   (the launcher forwards + finishes). Prints the median ms.
cold_start_ms() {
  local pkg="$1" launch="$2" disp="$3" runs="$4" i ms vals=()
  for ((i=0; i<runs; i++)); do
    "${ADB[@]}" shell am force-stop "$pkg" >/dev/null 2>&1 || true
    "${ADB[@]}" shell am kill-all >/dev/null 2>&1 || true
    sleep 2
    "${ADB[@]}" logcat -c >/dev/null 2>&1 || true
    "${ADB[@]}" shell am start -n "$pkg/$launch" >/dev/null 2>&1
    sleep 6
    ms=$("${ADB[@]}" logcat -d 2>/dev/null \
        | grep -oE "Displayed ${pkg}/${disp}: \+[0-9]+ms" | head -1 \
        | grep -oE '\+[0-9]+ms' | grep -oE '[0-9]+')
    [ -n "$ms" ] && vals+=("$ms")
    "${ADB[@]}" shell am force-stop "$pkg" >/dev/null 2>&1 || true
  done
  printf '%s\n' "${vals[@]}" | sort -n | awk '{a[NR]=$1} END{if(NR)print a[int((NR+1)/2)]}'
}
