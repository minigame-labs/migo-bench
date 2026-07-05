#!/usr/bin/env bash
# Capture the WebView shell: build+install, system cold-start, steady fps+mem+provenance.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

LABEL=""; OUT=""; DUR=60; COLD=3; SCEN=steady
while [[ $# -gt 0 ]]; do case "$1" in
  --label) LABEL="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;; --cold-runs) COLD="$2"; shift 2;;
  --scenario) SCEN="$2"; shift 2;;
  *) echo "unknown $1" >&2; exit 2;; esac; done
require_one_device

PKG=com.migo.bench.webview; ACT=.WebViewBenchActivity
SHELL_DIR="$DIR/../shells/webview-shell"; pfx="$OUT/$LABEL"

( cd "$SHELL_DIR" && ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}" ./gradlew -q :app:assembleDebug )
"${ADB[@]}" install -r -d "$SHELL_DIR/app/build/outputs/apk/debug/app-debug.apk" >/dev/null

if [ "$SCEN" = stress ]; then
  capture_stress "$PKG" "$ACT" "$DUR" "${pfx}_stress.txt"
  python3 "$DIR/stress_curve.py" webview < "${pfx}_stress.txt" > "$OUT/stress_webview.csv"
  echo "[webview] stress curve -> $OUT/stress_webview.csv"
else
  provenance_kv "$PKG" > "${pfx}_meta.txt"
  echo "cold_start_ms=$(cold_start_ms "$PKG" "$ACT" "$ACT" "$COLD")" >> "${pfx}_meta.txt"
  echo "game_ready_ms=$(game_ready_ms "$PKG" "$ACT" "$ACT" "$COLD")" >> "${pfx}_meta.txt"
  "${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true; sleep 2
  "${ADB[@]}" shell am start -n "$PKG/$ACT" $(_asset_extra) >/dev/null 2>&1; sleep 5
  capture_fps "$PKG" "$DUR" "$pfx" >> "${pfx}_meta.txt"   # writes ${pfx}_fps.txt + fps_source=...
  echo "cpu_pct=$(capture_cpu "$PKG" sandboxed_process)" >> "${pfx}_meta.txt"   # app + chromium renderer
  # Fair PSS: main process + chromium sandboxed renderer (dumpsys meminfo <pkg> omits the renderer).
  "${ADB[@]}" shell dumpsys meminfo 2>/dev/null | tr -d '\r' | python3 "$DIR/webview_pss.py" "$PKG" > "${pfx}_mem.txt"
  echo "[webview] captured: $(grep -E 'first_frame|cpu_pct|fps_source' "${pfx}_meta.txt" | tr '\n' ' ')"
fi
