#!/usr/bin/env bash
# Top-level runner: capture one runtime for one game on a device, append a
# provenance-stamped row to out/results.csv.
#
#   run.sh --runtime webview|migo --game bunnymark --device SERIAL \
#          [--scenario steady] [--duration 60] [--cold-runs 3] \
#          [--migo-aar local:PATH|release-tag:TAG|sha:SHA]   (required for migo)
set -euo pipefail
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

if [[ "$RUNTIME" == migo ]]; then
  [[ -n "$MIGO_AAR" ]] || { echo "ERROR: --migo-aar required for --runtime migo" >&2; exit 2; }
  migo_ver="$(bash "$DIR/resolve-migo-aar.sh" "$MIGO_AAR" "$DIR/../shells/migo-shell/app/libs/migo.aar")"
  bash "$DIR/capture-migo.sh" --label "$LABEL" --out "$OUT" --duration "$DUR" --cold-runs "$COLD"
elif [[ "$RUNTIME" == webview ]]; then
  bash "$DIR/capture-webview.sh" --label "$LABEL" --out "$OUT" --duration "$DUR" --cold-runs "$COLD"
else
  echo "ERROR: unknown runtime $RUNTIME (want webview|migo)" >&2; exit 2
fi

src="$(grep -oE 'fps_source=[a-z-]+' "$OUT/${LABEL}_meta.txt" | head -1 | cut -d= -f2 || true)"
cold="$(grep -oE 'cold_start_ms=[0-9]+' "$OUT/${LABEL}_meta.txt" | head -1 | cut -d= -f2 || true)"
[[ -f "$OUT/results.csv" ]] || python3 "$DIR/parse.py" --header-only > "$OUT/results.csv"
python3 "$DIR/parse.py" --label "$LABEL" --runtime "$RUNTIME" --game "$GAME" \
  --migo-version "$migo_ver" --fps-source "$src" \
  --meta "$OUT/${LABEL}_meta.txt" --mem "$OUT/${LABEL}_mem.txt" --fps "$OUT/${LABEL}_fps.txt" \
  --cold-ms "$cold" >> "$OUT/results.csv"
echo "[run] appended: $LABEL  fps_source=$src cold=${cold}ms migo=$migo_ver"
