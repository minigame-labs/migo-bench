#!/usr/bin/env bash
# Run the whole published comparison, the way MEASURING.md says to run it.
#
# The three-round interleaved protocol has existed as a written rule and no
# tool. Every published table was therefore assembled by hand, and its
# discipline was whatever the person running it remembered that night: whether
# the rounds really alternated, whether each cell waited for the same device
# state, whether a cell that failed got quietly re-run. RESULTS.md §5.2 records
# what that cost — the same unmodified WebView shell read anywhere from 380 to
# 524 ms across one night, which is larger than most of the effects being
# published.
#
# So this is the protocol as code:
#
#   * One round = both runtimes back to back on the same game. Order alternates
#     between rounds, so whatever drifts lands on the other runtime next time
#     instead of always on the same one.
#   * Every cell waits for the same cold state (lib.sh's `cold_gate`, shared
#     with the jitless driver — two copies of those thresholds is how two tables
#     stop being comparable), and the gate's outcome is recorded per row rather
#     than assumed.
#   * A failed cell is recorded as failed. It is not silently retried, because a
#     retry is a different sample and the table would not say so.
#   * Both shells are installed once, up front, and then left alone. That is
#     checklist item 2, and until now nothing enforced it: the capture scripts
#     reinstalled before every run, which resets the app's ART profile, so the
#     launches straight after ran without the AOT-compiled code the app has in
#     steady state. It is the mechanism that once put a 522 ms WebView first
#     frame into a published table when the steady-state figure was 354 ms.
#     After the install each shell is launched once and discarded, so the first
#     *measured* launch is not the first launch since the profile was reset.
#
# It writes out/matrix.csv: every results.csv column, prefixed with the round and
# suffixed with what the gate did. Rows are raw, one per run — take medians per
# cell when reporting, and keep the range, per MEASURING.md §7.
#
# Usage:
#   bench-matrix.sh --device SERIAL --migo-aar <spec>
#                   [--games "bunnymark endless-runner canvasmark"]
#                   [--rounds 3] [--duration 60] [--cold-runs 3]
#
#   --migo-aar  local:PATH | release-tag:TAG | sha:SHA. Prefer a tag: a table
#               anchored to a build nobody can download is not reproducible, and
#               RESULTS.md has been in exactly that state.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/../out"; mkdir -p "$OUT"

SERIAL=""; MIGO_AAR=""
GAMES="bunnymark endless-runner canvasmark"
ROUNDS=3; DUR=60; COLD=3
while [[ $# -gt 0 ]]; do case "$1" in
  --device) SERIAL="$2"; shift 2;;
  --migo-aar) MIGO_AAR="$2"; shift 2;;
  --games) GAMES="$2"; shift 2;;
  --rounds) ROUNDS="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;;
  --cold-runs) COLD="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

[[ -n "$SERIAL" ]] || { echo "ERROR: --device required" >&2; exit 2; }
[[ -n "$MIGO_AAR" ]] || { echo "ERROR: --migo-aar required (release-tag:vX.Y.Z for a publishable table)" >&2; exit 2; }

export SERIAL
# shellcheck source=lib.sh
. "$DIR/lib.sh"

MATRIX="$OUT/matrix.csv"
if [[ ! -f "$MATRIX" ]]; then
  { printf 'round,gate,'; python3 "$DIR/parse.py" --header-only; } > "$MATRIX"
fi
[[ -f "$OUT/results.csv" ]] || python3 "$DIR/parse.py" --header-only > "$OUT/results.csv"

echo "[matrix] device=$SERIAL rounds=$ROUNDS games='$GAMES'"
echo "[matrix] migo=$MIGO_AAR duration=${DUR}s cold-runs=$COLD"

# ---- install once, settle, then never install again --------------------
# One throwaway run per runtime does the installing (lib.sh's
# install_if_changed makes every later run a no-op, since the APK does not
# change) and gives ART a launch to profile before anything is recorded. Its
# row is dropped: it is the one run that carries the fresh-install penalty.
echo "[matrix] priming: installing both shells and discarding one run each"
for runtime in webview migo; do
  prime=(--runtime "$runtime" --game "${GAMES%% *}" --device "$SERIAL" --duration 10 --cold-runs 1)
  [[ "$runtime" == migo ]] && prime+=(--migo-aar "$MIGO_AAR")
  before="$(wc -l < "$OUT/results.csv")"
  if bash "$DIR/run.sh" "${prime[@]}" >"$OUT/matrix_prime_${runtime}.log" 2>&1; then
    after="$(wc -l < "$OUT/results.csv")"
    (( after > before )) && sed -i '$d' "$OUT/results.csv"
    echo "[matrix]   $runtime primed (row discarded)"
  else
    echo "[matrix]   $runtime prime FAILED -- see $OUT/matrix_prime_${runtime}.log" >&2
    exit 1
  fi
done

failures=0
for (( round=1; round<=ROUNDS; round++ )); do
  if (( round % 2 == 1 )); then runtimes=(webview migo); else runtimes=(migo webview); fi
  for game in $GAMES; do
    for runtime in "${runtimes[@]}"; do
      echo "[matrix] round $round | $game | $runtime"
      gate="$(cold_gate "r${round}/${game}/${runtime}")"
      echo "[matrix]   gate: $gate"
      case "$gate" in TIMEOUT*) echo "[matrix]   WARNING: this row is not temperature-gated";; esac

      args=(--runtime "$runtime" --game "$game" --device "$SERIAL"
            --duration "$DUR" --cold-runs "$COLD")
      [[ "$runtime" == migo ]] && args+=(--migo-aar "$MIGO_AAR")

      before="$(wc -l < "$OUT/results.csv")"
      log="$OUT/matrix_${round}_${game}_${runtime}.log"
      if ! bash "$DIR/run.sh" "${args[@]}" >"$log" 2>&1; then
        echo "[matrix]   RUN FAILED -- $log" >&2
        failures=$((failures + 1))
        continue
      fi
      after="$(wc -l < "$OUT/results.csv")"
      if (( after <= before )); then
        echo "[matrix]   run appended no row -- $log" >&2
        failures=$((failures + 1))
        continue
      fi
      printf '%s,"%s",%s\n' "$round" "$gate" "$(tail -1 "$OUT/results.csv")" >> "$MATRIX"
      echo "[matrix]   recorded"
    done
  done
done

echo "[matrix] done -> $MATRIX ($failures failed cell(s))"
# A partly-filled matrix is still worth having, but the caller must be able to
# tell. Medians over a cell that lost a round are not the same measurement.
[[ "$failures" -eq 0 ]] || exit 1
