#!/usr/bin/env bash
# What a jitless V8 costs, measured on hardware instead of assumed.
#
# HarmonyOS 5.0.0(12) stopped letting anonymous memory become executable, so no
# third-party VM may JIT on NEXT. Migo bundles V8, so on NEXT it runs
# interpreted. Nothing about Migo's performance on NEXT may be claimed until the
# size of that penalty is a measured number, and this script is how the number
# is produced.
#
# `--jitless` on hardware we can actually run is the proxy. It is faithful on
# the axis that matters -- V8 stops generating code and interprets -- and the
# engine build flag that turns it on lives in the migo tree as
# `--features v8-jitless` (scripts/build-aar.sh --jitless).
#
# READ THIS BEFORE READING ANY NUMBER THIS SCRIPT PRODUCES: jitless does not
# make WebAssembly slow, it removes it. `typeof WebAssembly` is `undefined` and
# instantiating a module throws, because V8 cannot compile one without
# generating code. Every game measured here is pure JS. Content that ships
# `.wasm` -- which is most Cocos and every Unity export, packaged as `.wasm.br`
# -- does not run slower on a jitless engine. It does not run. A ratio from this
# table describes the games in it and nothing else.
#
# Method, from MEASURING.md, not invented here:
#   * Both arms come from ONE engine tree, differing only in the feature. They
#     therefore embed the same V8 startup snapshot, so a startup difference is
#     the flag and not a bootstrap difference.
#   * Rounds are interleaved and the arm order alternates between them, so an
#     order effect cannot masquerade as the effect.
#   * Every run is gated on the same cold state stress-ab.sh gates on
#     (soc <= 35 C AND cpu7 unthrottled), and the gate reports its own timeout --
#     a silent "waited forever then proceeded" turns a gated run into an ungated
#     one that still looks gated.
#   * A freshly installed APK is not in steady state. This script does NOT get
#     to discard that launch -- run.sh installs and measures in one call -- so
#     the first launch after each install lands inside the --cold-runs set that
#     the reported cold-start figure reduces over. Both arms are installed the
#     same number of times, so the effect is symmetric, but it is a reason to
#     read the startup columns as noisier than the steady-state ones rather than
#     as clean.
#
# Usage:
#   jitless-ab.sh --device SERIAL --jit-aar PATH --jitless-aar PATH
#                 [--games "bunnymark canvasmark endless-runner"]
#                 [--rounds 3] [--duration 60] [--cold-runs 3]
#                 [--scenario steady|stress]
#                 [--label-a NAME] [--label-b NAME] [--self-test]
#
# --self-test runs one build against itself. Everything that then appears
# between the two "arms" is noise, which is the only way to know what a
# difference has to be before this harness can call it a difference at all.
# Without that number every published comparison is unanchored: 15 ms and 150 ms
# read the same on the page. It is the one case where the identical-AAR guard
# below is wrong, so it takes an explicit flag rather than being inferred.
#
# The two arms are labelled `jit` and `jitless` by default because that is what
# this was built for, but the driver is arm-agnostic: any two AARs from one tree
# differing in one thing. Rename them when they are something else -- a row
# labelled `jitless` that is really "packed relocations off" is the kind of
# mislabelled data that outlives whoever produced it.
#
# --scenario stress runs bunnymark's sprite ramp instead of the steady window.
# It exists because the steady table cannot answer the question the whole
# measurement is for: all three games sit at a vsync-capped 60 fps with headroom,
# and a capped metric has no power to show a difference. The ramp removes the cap
# — fps then falls where capability runs out, which is the thing jitless actually
# changes. Curves land in out/stress_migo_<arm>_r<round>.csv, one per cell.
#
# Writes out/jitless_ab.csv: every results.csv column, prefixed with the round
# and arm and suffixed with what the temperature gate did. Rows are raw, one per
# run -- take medians per cell when reporting, and keep the range.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/../out"; mkdir -p "$OUT"

SERIAL=""; JIT_AAR=""; JITLESS_AAR=""
GAMES="bunnymark canvasmark endless-runner"
ROUNDS=3; DUR=60; COLD=3; SCEN=steady
LABEL_A=jit; LABEL_B=jitless; SELF_TEST=false
while [[ $# -gt 0 ]]; do case "$1" in
  --device) SERIAL="$2"; shift 2;;
  --jit-aar) JIT_AAR="$2"; shift 2;;
  --jitless-aar) JITLESS_AAR="$2"; shift 2;;
  --games) GAMES="$2"; shift 2;;
  --rounds) ROUNDS="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;;
  --cold-runs) COLD="$2"; shift 2;;
  --scenario) SCEN="$2"; shift 2;;
  --self-test) SELF_TEST=true; LABEL_A=A; LABEL_B=B; shift;;
  --label-a) LABEL_A="$2"; shift 2;;
  --label-b) LABEL_B="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done

[[ -n "$SERIAL" ]] || { echo "ERROR: --device required" >&2; exit 2; }
case "$SCEN" in
  steady) ;;
  stress) GAMES="bunnymark";;   # the ramp is Pixi-ticker driven; run.sh enforces this too
  *) echo "ERROR: --scenario wants steady or stress" >&2; exit 2;;
esac
for spec in "$JIT_AAR" "$JITLESS_AAR"; do
  [[ -n "$spec" ]] || { echo "ERROR: --jit-aar and --jitless-aar are both required" >&2; exit 2; }
  [[ -f "$spec" ]] || { echo "ERROR: not a file: $spec" >&2; exit 2; }
done
# Two paths that resolve to the same bytes would produce a table comparing a
# build against itself, and every cell would look like noise rather than a bug.
if cmp -s "$JIT_AAR" "$JITLESS_AAR"; then
  if [[ "$SELF_TEST" != true ]]; then
    echo "ERROR: --jit-aar and --jitless-aar are byte-identical; one of them is not the build you think it is" >&2
    echo "       (pass --self-test if measuring the harness's own noise floor is the point)" >&2
    exit 2
  fi
  echo "[ab] SELF TEST: both arms are the same build. Any difference below is noise."
fi

ADB_BIN="${ANDROID_HOME:+$ANDROID_HOME/platform-tools/adb}"
[[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || ADB_BIN="$HOME/Android/Sdk/platform-tools/adb"
[[ -x "$ADB_BIN" ]] || ADB_BIN="adb"
ADB=("$ADB_BIN" -s "$SERIAL")

PKG=com.migo.bench.migo
LAUNCH=.BenchGameActivity

# The gate lives in lib.sh, shared with the webview-vs-migo matrix driver.
# Two copies of it would let two tables drift apart on the one thing that makes
# them comparable.
# shellcheck source=lib.sh
SERIAL="$SERIAL" . "$DIR/lib.sh"

AB="$OUT/jitless_ab.csv"
if [[ ! -f "$AB" ]]; then
  { printf 'round,arm,gate,'; python3 "$DIR/parse.py" --header-only; } > "$AB"
fi
[[ -f "$OUT/results.csv" ]] || python3 "$DIR/parse.py" --header-only > "$OUT/results.csv"

echo "[ab] device=$SERIAL rounds=$ROUNDS games='$GAMES' duration=${DUR}s cold-runs=$COLD"
echo "[ab] jit     = $JIT_AAR"
echo "[ab] jitless = $JITLESS_AAR"

for (( round=1; round<=ROUNDS; round++ )); do
  # Alternate which arm goes first. Whatever drifts across a round then lands on
  # the other arm next time instead of always on the same one.
  if (( round % 2 == 1 )); then arms=("$LABEL_A" "$LABEL_B"); else arms=("$LABEL_B" "$LABEL_A"); fi

  for game in $GAMES; do
    for arm in "${arms[@]}"; do
      if [[ "$arm" == "$LABEL_A" ]]; then aar="$JIT_AAR"; else aar="$JITLESS_AAR"; fi

      echo "[ab] round $round | $game | $arm"
      gate="$(cold_gate "r${round}/${game}/${arm}")"
      echo "[ab]   gate: $gate"
      case "$gate" in TIMEOUT*) echo "[ab]   WARNING: this row is not temperature-gated";; esac

      before="$(wc -l < "$OUT/results.csv")"
      bash "$DIR/run.sh" --runtime migo --game "$game" --device "$SERIAL" \
        --migo-aar "local:$aar" --duration "$DUR" --cold-runs "$COLD" --scenario "$SCEN" \
        >"$OUT/jitless_ab_${round}_${game}_${arm}.log" 2>&1 || {
          echo "[ab]   RUN FAILED -- see $OUT/jitless_ab_${round}_${game}_${arm}.log" >&2
          continue
        }
      # The stress scenario writes a curve and appends no steady row. Keep each
      # cell's curve under its own name -- run.sh overwrites stress_migo.csv every
      # time, so without this the last arm to run would be the only one left.
      if [[ "$SCEN" == stress ]]; then
        if [[ -f "$OUT/stress_migo.csv" ]]; then
          mv "$OUT/stress_migo.csv" "$OUT/stress_migo_${arm}_r${round}.csv"
          echo "[ab]   curve -> stress_migo_${arm}_r${round}.csv ($(( $(wc -l < "$OUT/stress_migo_${arm}_r${round}.csv") - 1 )) points)"
        else
          echo "[ab]   stress run produced no curve" >&2
        fi
        continue
      fi
      after="$(wc -l < "$OUT/results.csv")"
      if (( after <= before )); then
        echo "[ab]   run appended no row; nothing to record" >&2
        continue
      fi
      # Take the row, then take it back out of results.csv.
      #
      # run.sh appends to the shared steady-state table, and these rows are not
      # steady-state Migo numbers -- half of them are a jitless build. Left
      # there they are indistinguishable from a normal run (same `runtime=migo`,
      # same version string, since both arms come from one tree), so anything
      # that reads results.csv for "what Migo does" would quietly average a
      # crippled build into a published claim. The portal's benchmark figures
      # are transcribed from exactly that file.
      printf '%s,%s,"%s",%s\n' "$round" "$arm" "$gate" "$(tail -1 "$OUT/results.csv")" >> "$AB"
      sed -i '$d' "$OUT/results.csv"
      echo "[ab]   recorded: $(tail -1 "$AB" | cut -d, -f1-3,13-)"
    done
  done
done

echo "[ab] done -> $AB"
