#!/usr/bin/env bash
# Capture the Migo shell: build+install (AAR already staged at app/libs/migo.aar
# by run.sh), system cold-start (Displayed for BenchGameActivity), steady fps+mem.
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

PKG=com.migo.bench.migo; LAUNCH=.LauncherActivity; DISP=.BenchGameActivity
SHELL_DIR="$DIR/../shells/migo-shell"; pfx="$OUT/$LABEL"

[[ -f "$SHELL_DIR/app/libs/migo.aar" ]] || { echo "ERROR: migo.aar not staged (run resolve-migo-aar.sh)" >&2; exit 2; }
( cd "$SHELL_DIR" && ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}" ./gradlew -q :app:assembleDebug )
"${ADB[@]}" install -r -d "$SHELL_DIR/app/build/outputs/apk/debug/app-debug.apk" >/dev/null

if [ "$SCEN" = stress ]; then
  capture_stress "$PKG" "$LAUNCH" "$DUR" "${pfx}_stress.txt"
  python3 "$DIR/stress_curve.py" migo < "${pfx}_stress.txt" > "$OUT/stress_migo.csv"
  echo "[migo] stress curve -> $OUT/stress_migo.csv"
else
  provenance_kv "$PKG" > "${pfx}_meta.txt"
  echo "cold_start_ms=$(cold_start_ms "$PKG" "$LAUNCH" "$DISP" "$COLD")" >> "${pfx}_meta.txt"
  echo "game_ready_ms=$(game_ready_ms "$PKG" "$DISP" "$LAUNCH" "$COLD")" >> "${pfx}_meta.txt"
  "${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true; sleep 2
  "${ADB[@]}" shell am start -n "$PKG/$LAUNCH" >/dev/null 2>&1; sleep 8   # migo game load is async
  capture_fps "$PKG" "$DUR" "$pfx" >> "${pfx}_meta.txt"
  echo "cpu_pct=$(capture_cpu "$PKG")" >> "${pfx}_meta.txt"
  capture_mem "$PKG" "${pfx}_mem.txt"
  echo "[migo] captured: $(grep -E 'cold_start_ms|game_ready_ms|cpu_pct|fps_source' "${pfx}_meta.txt" | tr '\n' ' ')"
fi
