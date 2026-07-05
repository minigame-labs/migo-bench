#!/usr/bin/env bash
# Top-level runner: capture one runtime for one game on a device, append a
# provenance-stamped row to out/results.csv.
#
#   run.sh --runtime webview|migo --game bunnymark --device SERIAL \
#          [--scenario steady] [--duration 60] [--cold-runs 3] \
#          [--migo-aar local:PATH|release-tag:TAG|sha:SHA]   (required for migo)
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUNTIME=""; GAME=bunnymark; DEVICE=""; SCEN=steady; DUR=60; COLD=3; MIGO_AAR=""
while [[ $# -gt 0 ]]; do case "$1" in
  --runtime) RUNTIME="$2"; shift 2;; --game) GAME="$2"; shift 2;;
  --device) DEVICE="$2"; shift 2;; --scenario) SCEN="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;; --cold-runs) COLD="$2"; shift 2;;
  --migo-aar) MIGO_AAR="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;; esac; done
[[ -n "$RUNTIME" ]] || { echo "ERROR: --runtime required" >&2; exit 2; }

export SERIAL="$DEVICE"
OUT="$DIR/../out"; mkdir -p "$OUT"
LABEL="${GAME}_${RUNTIME}"
migo_ver="n/a"

# The stress scenario needs the (generated) bunnymark-stress asset bundled into
# the shell APK, so regenerate it before the capture builds the shell.
[[ "$SCEN" == stress ]] && bash "$DIR/make-stress-game.sh"

if [[ "$RUNTIME" == migo ]]; then
  [[ -n "$MIGO_AAR" ]] || { echo "ERROR: --migo-aar required for --runtime migo" >&2; exit 2; }
  migo_ver="$(bash "$DIR/resolve-migo-aar.sh" "$MIGO_AAR" "$DIR/../shells/migo-shell/app/libs/migo.aar")"
  bash "$DIR/capture-migo.sh" --label "$LABEL" --out "$OUT" --duration "$DUR" --cold-runs "$COLD" --scenario "$SCEN"
elif [[ "$RUNTIME" == webview ]]; then
  bash "$DIR/capture-webview.sh" --label "$LABEL" --out "$OUT" --duration "$DUR" --cold-runs "$COLD" --scenario "$SCEN"
else
  echo "ERROR: unknown runtime $RUNTIME (want webview|migo)" >&2; exit 2
fi

if [[ "$SCEN" == stress ]]; then
  echo "[run] stress curve written to $OUT/stress_${RUNTIME}.csv (migo=$migo_ver)"
  exit 0
fi

metaf="$OUT/${LABEL}_meta.txt"
mval() { grep -oE "$1=[0-9a-z.-]+" "$metaf" | head -1 | cut -d= -f2 || true; }
src="$(mval fps_source)"; cold="$(mval cold_start_ms)"
gready="$(mval game_ready_ms)"; cpu="$(mval cpu_pct)"
[[ -f "$OUT/results.csv" ]] || python3 "$DIR/parse.py" --header-only > "$OUT/results.csv"
python3 "$DIR/parse.py" --label "$LABEL" --runtime "$RUNTIME" --game "$GAME" \
  --migo-version "$migo_ver" --fps-source "$src" \
  --meta "$metaf" --mem "$OUT/${LABEL}_mem.txt" --fps "$OUT/${LABEL}_fps.txt" \
  --cold-ms "$cold" --game-ready-ms "$gready" --cpu-pct "$cpu" >> "$OUT/results.csv"
echo "[run] appended: $LABEL  first_frame=${cold}ms game_ready=${gready}ms cpu=${cpu}% fps_src=$src migo=$migo_ver"
