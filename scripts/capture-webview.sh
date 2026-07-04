#!/usr/bin/env bash
# Capture the WebView shell: build+install, system cold-start, steady fps+mem+provenance.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

LABEL=""; OUT=""; DUR=60; COLD=3
while [[ $# -gt 0 ]]; do case "$1" in
  --label) LABEL="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;; --cold-runs) COLD="$2"; shift 2;;
  *) echo "unknown $1" >&2; exit 2;; esac; done
require_one_device

PKG=com.migo.bench.webview; ACT=.WebViewBenchActivity
SHELL_DIR="$DIR/../shells/webview-shell"; pfx="$OUT/$LABEL"

( cd "$SHELL_DIR" && ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}" ./gradlew -q :app:assembleDebug )
"${ADB[@]}" install -r -d "$SHELL_DIR/app/build/outputs/apk/debug/app-debug.apk" >/dev/null

provenance_kv "$PKG" > "${pfx}_meta.txt"
echo "cold_start_ms=$(cold_start_ms "$PKG" "$ACT" "$ACT" "$COLD")" >> "${pfx}_meta.txt"

"${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true; sleep 2
"${ADB[@]}" shell am start -n "$PKG/$ACT" >/dev/null 2>&1; sleep 5
capture_fps "$PKG" "$DUR" "$pfx" >> "${pfx}_meta.txt"   # writes ${pfx}_fps.txt + fps_source=...
# Fair PSS: main process + chromium sandboxed renderer (dumpsys meminfo <pkg> omits the renderer).
"${ADB[@]}" shell dumpsys meminfo 2>/dev/null | tr -d '\r' | python3 "$DIR/webview_pss.py" "$PKG" > "${pfx}_mem.txt"
echo "[webview] captured: $(grep -E 'cold_start_ms|fps_source' "${pfx}_meta.txt" | tr '\n' ' ')"
