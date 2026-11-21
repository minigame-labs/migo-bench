#!/usr/bin/env bash
# Where Migo's native heap goes, by the call site that allocated it.
#
# meminfo says how big the native heap is; it cannot say who holds it. heapprofd (perfetto) samples every malloc and
# free in the shell's process from its first instruction, and the trace is symbolized against the libmigo.so that ran.
# A release library is stripped, so profile an AAR built from the same tree with its symbols kept
# (`CARGO_PROFILE_RELEASE_STRIP=false` and the config's `-s` / `--strip-all` dropped: same code, same layout, a symbol
# table on top), and pass that same library to --symbols. perfetto matches libraries by build id, so it must be the
# build that was installed, not one built later.
#
#   heap-profile.sh --device SERIAL --migo-aar local:PATH --symbols DIR [--game bunnymark] [--secs 30] [--out DIR]
#
# Needs: the debug migo shell (heapprofd profiles debuggable apps) on Android 10 or newer; on the host, traceconv and
# trace_processor_shell (PERFETTO_TOOLS, default ~/tools/perfetto) and llvm-symbolizer on PATH (the NDK's will do).
# Writes <out>/heap_<game>.pftrace, .symbolized.pftrace and heap_<game>.txt: live bytes when the window closes, by
# component and by site (scripts/heap_sites.sql). Sampled: the figures are heapprofd's estimates at 4 KiB sampling.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE=""; MIGO_AAR=""; SYMBOLS=""; GAME=bunnymark; SECS=30; OUT="$DIR/../out/heap"
while [[ $# -gt 0 ]]; do case "$1" in
  --device) DEVICE="$2"; shift 2;; --migo-aar) MIGO_AAR="$2"; shift 2;; --symbols) SYMBOLS="$2"; shift 2;;
  --game) GAME="$2"; shift 2;; --secs) SECS="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;; esac; done
[[ -n "$DEVICE" && -n "$MIGO_AAR" && -d "$SYMBOLS" ]] || { echo "usage: $0 --device SERIAL --migo-aar SPEC --symbols DIR [--game G] [--secs N] [--out DIR]" >&2; exit 2; }
export SERIAL="$DEVICE"
[[ "$GAME" == bunnymark ]] || export GAME_ASSET="game-$GAME"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
mkdir -p "$OUT"
PKG=com.migo.bench.migo; LAUNCH=.BenchGameActivity
SHELL_DIR="$DIR/../shells/migo-shell"

bash "$DIR/resolve-migo-aar.sh" "$MIGO_AAR" "$SHELL_DIR/app/libs/migo.aar" > /dev/null
( cd "$SHELL_DIR" && ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}" ./gradlew -q :app:assembleDebug )
install_if_changed "$PKG" "$SHELL_DIR/app/build/outputs/apk/debug/app-debug.apk"

trace="/data/misc/perfetto-traces/migo-heap.pftrace"
"${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"${ADB[@]}" shell rm -f "$trace" >/dev/null 2>&1 || true
# The process does not exist yet: heapprofd attaches when a process with this name starts (startup profiling), so
# the window covers everything from the first allocation. It closes on its own after duration_ms and dumps then.
config="buffers { size_kb: 262144 fill_policy: DISCARD }
data_sources { config { name: \"android.heapprofd\" target_buffer: 0 heapprofd_config {
  sampling_interval_bytes: 4096 process_cmdline: \"$PKG\" shmem_size_bytes: 33554432 block_client: true } } }
duration_ms: $(( (SECS + 10) * 1000 ))"
pid="$(printf '%s\n' "$config" | "${ADB[@]}" shell perfetto --txt -c - -o "$trace" --background | tr -d '\r' | tail -1)"
[[ "$pid" =~ ^[0-9]+$ ]] || { echo "ERROR: perfetto did not start (got '$pid')" >&2; exit 1; }
sleep 3
"${ADB[@]}" shell am start -n "$PKG/$LAUNCH" $(_migo_launch_extras) $(_asset_extra) >/dev/null
echo "[heap] perfetto $pid recording $GAME for ${SECS}s"
while "${ADB[@]}" shell kill -0 "$pid" >/dev/null 2>&1; do sleep 2; done
raw="$OUT/heap_${GAME}.pftrace"
"${ADB[@]}" pull "$trace" "$raw" >/dev/null
"${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true
echo "[heap] trace: $raw ($(wc -c < "$raw") bytes)"

TOOLS="${PERFETTO_TOOLS:-$HOME/tools/perfetto}"
TRACECONV="$TOOLS/traceconv"; TP="$TOOLS/trace_processor_shell"; [[ -x "$TP" ]] || TP="$TOOLS/trace_processor"
if [[ ! -x "$TRACECONV" || ! -x "$TP" ]]; then
  echo "[heap] no perfetto tools in $TOOLS: symbolize and query elsewhere with scripts/heap_sites.sql"; exit 0
fi
symbolized="$OUT/heap_${GAME}.symbolized.pftrace"
PERFETTO_BINARY_PATH="$SYMBOLS" "$TRACECONV" symbolize "$raw" "$OUT/heap_${GAME}.symbols.pb"
cat "$raw" "$OUT/heap_${GAME}.symbols.pb" > "$symbolized"
"$TP" -q "$DIR/heap_sites.sql" "$symbolized" 2>/dev/null | tee "$OUT/heap_${GAME}.txt"
