#!/usr/bin/env bash
# On-device JS hotspot profiler for the Migo runtime.
#
# Uses V8's built-in --prof sampling profiler (SIGPROF timer based -> works on
# devices where perf_event is blocked, e.g. Huawei/EMUI). Enables it via the
# debug-only /data/local/tmp/v8flags.txt hook in host_runtime.rs (compiled out
# of release builds), runs a game to a steady state, pulls the v8.log, and
# attributes every sample to a JS function with tickparse.mjs.
#
# Requires: a DEBUG migo AAR in the shell (the flag hook is #[cfg(debug_assertions)]).
#
# Usage:
#   scripts/profile-migo.sh [--game <asset>] [--secs <n>] [--flags "<extra v8 flags>"]
# Examples:
#   scripts/profile-migo.sh                              # game-stress, 55s
#   scripts/profile-migo.sh --game game --secs 30        # the plain game
#   scripts/profile-migo.sh --flags "--trace-deopt"      # + deopt tracing to logcat
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"

PKG="${PKG:-com.migo.bench.migo}"
GAME="game-stress"
SECS=55
EXTRA_FLAGS=""
OUT="${OUT:-$DIR/../out/profile}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --game)  GAME="$2"; shift 2;;
    --secs)  SECS="$2"; shift 2;;
    --flags) EXTRA_FLAGS="$2"; shift 2;;
    --pkg)   PKG="$2"; shift 2;;
    --out)   OUT="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
mkdir -p "$OUT"
require_one_device

LOGDEV="/data/data/$PKG/files/v8.log"
FLAGS="--prof --no-logfile-per-isolate --logfile=$LOGDEV${EXTRA_FLAGS:+ $EXTRA_FLAGS}"

echo ">> V8 flags: $FLAGS"
adbsh "echo '$FLAGS' > /data/local/tmp/v8flags.txt"
adbsh am force-stop "$PKG" >/dev/null 2>&1 || true
adbsh "run-as $PKG rm -f files/v8.log" >/dev/null 2>&1 || true

echo ">> launching $PKG game_asset=$GAME"
adbsh am start -n "$PKG/.LauncherActivity" --es game_asset "$GAME" >/dev/null

# Wait for the game to reach steady state, showing progress.
for ((t=10; t<=SECS; t+=10)); do
  "${ADB[@]}" shell sleep 10
  sz=$(adbsh "run-as $PKG stat -c %s files/v8.log 2>/dev/null" | tr -d '\r')
  info=$("${ADB[@]}" logcat -d 2>/dev/null | grep -oE 'bunnies=[0-9]+|fps=[0-9]+' | tail -2 | tr '\n' ' ')
  echo "   t=${t}s log=${sz}B  ${info}"
done

echo ">> clean finish (BACK) to flush v8.log"
adbsh input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
adbsh input keyevent KEYCODE_BACK >/dev/null 2>&1 || true
"${ADB[@]}" shell sleep 2

# Disarm the profiler so subsequent normal runs are unaffected.
adbsh "echo '' > /data/local/tmp/v8flags.txt"

LOCAL="$OUT/v8.$GAME.log"
"${ADB[@]}" exec-out run-as "$PKG" cat files/v8.log > "$LOCAL"
echo ">> pulled $(wc -l < "$LOCAL") lines -> $LOCAL"
echo
node "$DIR/tickparse.mjs" "$LOCAL"
