#!/usr/bin/env bash
# macOS: Migo against WKWebView -- same release, same game, same Mac, one session.
#
# The iOS harness's question (scripts/ios-ab.sh) asked on a Mac, where the two
# arms are genuinely different engines: Migo runs the game's JavaScript on V8
# with JIT in the app's own process and renders through Skia on ANGLE/Metal;
# the WKWebView arm runs it in WebKit's WebContent process on JavaScriptCore and
# renders in WebKit's GPU process. Steady state only, as on iOS (MEASURING.md §6).
#
#   arm migo     shells/macos MigoBenchMac: migo-shell's game package in a
#                MigoGameView, linked against the release's Apple SDK
#   arm webview  shells/macos WebViewBenchMac: webview-shell's page in a WKWebView
#
# An arm is its app process plus the WebKit helpers it started -- the rule the
# Android and iOS harnesses apply. Helpers are the com.apple.WebKit.* processes
# that started after the app did; the harness refuses to measure with any such
# process already running, so none can be another app's.
#
# Per cell: 30 s idle; launch the arm into a window of fixed size; the app proves
# after the settle that its window is visible and drawing and prints
# `[bench] measuring`; then for the window the harness reads every process's
# CPU time at both ends (the arm's CPU is the difference over the wall time, in
# percent of one core), samples its phys_footprint every 10 s (the median is
# reported), and takes the game's own fps telemetry lines that arrived inside
# it. Rounds interleave and alternate order (§3). A cell during which the CPU
# was throttled (`pmset -g therm` CPU_Scheduler_Limit below 100) is kept in the
# CSV and left out of the summary.
#
# The GPU must be pinned for the session (`sudo pmset -a gpuswitch 1` for the
# discrete GPU, 0 for the integrated one) on a Mac that has two: both apps
# declare automatic switching, and without a pin the arms could run on
# different GPUs. The harness refuses an unpinned two-GPU Mac and records which.
# The display must be awake and the session unlocked: the apps refuse to measure
# an occluded window. Nothing else should be running.
#
# Usage (on the Mac, from the repository):
#   macos-ab.sh --version vX.Y.Z [--games "bunnymark endless-runner canvasmark"]
#               [--rounds 3] [--duration 60] [--arms "migo webview"]
#   `--games "calib-idle calib-busy calib-mem"` runs the measurement calibration
#   (scripts/macos-validate-measurement.sh reads it).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC="$DIR/../shells/macos"
OUT="$DIR/../out"; mkdir -p "$OUT"
VERSION=""
GAMES="bunnymark endless-runner canvasmark"; ROUNDS=3; DUR=60; SETTLE=8; ARMS="migo webview"
while [[ $# -gt 0 ]]; do case "$1" in
  --version) VERSION="$2"; shift 2;;
  --games) GAMES="$2"; shift 2;;
  --arms) ARMS="$2"; shift 2;;
  --rounds) ROUNDS="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done
[[ -n "$VERSION" ]] || { echo "ERROR: --version is required" >&2; exit 2; }

asset() {
  case "$1" in
    bunnymark) echo game ;;
    calib-*) echo "$1" ;;
    *) echo "game-$1" ;;
  esac
}
landscape() {
  local manifest="$DIR/../shells/migo-shell/app/src/main/assets/$(asset "$1")/game.json"
  [[ "$1" == calib-* ]] && manifest="$DIR/../shells/ios/calibration/$1/game.json"
  python3 -c 'import json,sys; print("YES" if json.load(open(sys.argv[1])).get("deviceOrientation") == "landscape" else "NO")' \
    "$manifest"
}
exe() { [[ "$1" == migo ]] && echo MigoBenchMac || echo WebViewBenchMac; }

# Which GPU renders. A two-GPU Mac lists two chipsets; the pin is pmset's.
GPUS="$(system_profiler SPDisplaysDataType 2>/dev/null | sed -n 's/^ *Chipset Model: //p' | paste -sd '+' -)"
SWITCH="$(pmset -g | awk '$1 == "gpuswitch" {print $2}')"
if [[ "$GPUS" == *+* ]]; then
  case "$SWITCH" in
    0) GPU="integrated (${GPUS%%+*})";;
    1) GPU="discrete (${GPUS##*+})";;
    *) echo "ERROR: this Mac has two GPUs ($GPUS) and gpuswitch is '$SWITCH'; pin one for the session" \
         "(sudo pmset -a gpuswitch 1 for discrete, 0 for integrated)" >&2; exit 2;;
  esac
else
  GPU="$GPUS"
fi

# Nothing WebKit may be running before a cell starts, or a helper could not be
# attributed to the arm that is measured.
webkit_pids() { pgrep -f 'com\.apple\.WebKit\.(WebContent|GPU|Networking)' || true; }
if [[ -n "$(webkit_pids)" ]]; then
  echo "ERROR: WebKit processes are already running (Safari, Mail, another app with a web view):" >&2
  ps -o pid=,command= -p "$(webkit_pids | paste -sd, -)" >&2
  echo "quit what owns them first" >&2; exit 2
fi

# The release's Apple SDK, exactly as published.
if [[ "$(cat "$MAC/.sdk-version" 2>/dev/null)" != "$VERSION" ]]; then
  tmp="$(mktemp -d)"
  gh release download "$VERSION" -R minigame-labs/migo-runtime -p "migo-${VERSION#v}-apple-sdk.zip" -D "$tmp"
  unzip -q "$tmp"/*.zip -d "$tmp/u"
  rm -rf "$MAC/sdk" && mv "$tmp/u/MigoApple" "$MAC/sdk" && rm -rf "$tmp"
  echo "$VERSION" > "$MAC/.sdk-version"
fi

# Built once per SDK version, for this Mac's architecture.
( cd "$MAC" && xcodegen generate -q )
for arm in $ARMS; do
  xcodebuild -project "$MAC/MigoBenchMac.xcodeproj" -scheme "$(exe $arm)" -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$MAC/build/$VERSION" -quiet build
done
app() { echo "$MAC/build/$VERSION/Build/Products/Release/$(exe "$1").app/Contents/MacOS/$(exe "$1")"; }

MODEL="$(sysctl -n hw.model);$(sw_vers -productVersion)"
SESSION="$(date -u +%Y%m%dT%H%M%SZ)"
CSV="$OUT/macos_ab_${SESSION}.csv"
echo "round,arm,game,mac,macos,gpu,migo_version,fps_median,fps_min,cpu_pct,footprint_mb,cpu_limit_min,samples,processes,breakdown" > "$CSV"
WORK="$(mktemp -d)"

stop_ours() {
  pkill -x MigoBenchMac 2>/dev/null || true
  pkill -x WebViewBenchMac 2>/dev/null || true
  # A WebKit helper outlives its app by a moment; wait it out, then refuse to
  # go on if one stays -- it would be counted in the next cell.
  for _ in $(seq 1 20); do [[ -z "$(webkit_pids)" ]] && return 0; sleep 0.5; done
  echo "[macos-ab] WebKit processes did not exit: $(webkit_pids | paste -sd' ' -)" >&2
  return 1
}

# CPU seconds a process has used, from `ps -o time=` ([[dd-]hh:]mm:ss.cc).
cpu_of() {
  ps -o time= -p "$1" 2>/dev/null | python3 -c '
import sys
t = sys.stdin.read().strip()
if not t: sys.exit(1)
days, _, t = t.rpartition("-")
parts = [float(p) for p in t.split(":")]
seconds = sum(v * 60 ** i for i, v in enumerate(reversed(parts)))
print(seconds + (int(days) * 86400 if days else 0))'
}

# phys_footprint of one process, MiB.
footprint_of() {
  footprint -p "$1" 2>/dev/null | python3 -c '
import re, sys
m = re.search(r"phys_footprint:\s*([\d.]+)\s*(KB|MB|GB)", sys.stdin.read())
if not m: sys.exit(1)
print(float(m.group(1)) * {"KB": 1 / 1024, "MB": 1, "GB": 1024}[m.group(2)])'
}

cpu_limit() { pmset -g therm 2>/dev/null | awk '/CPU_Scheduler_Limit/ {print $3}' | tail -1; }

cell() {  # <round> <arm> <game>; round 0 is the warm-up and is not recorded
  local round="$1" arm="$2" game="$3" pfx="$WORK/$1-$2-$3"
  stop_ours || return 1
  sleep 30
  # Launched directly rather than through `open`, so its output is the
  # harness's. MIGO_CAPI_LOG=error puts the Migo arm's console.error lines --
  # the fps telemetry -- on its stderr; the WebView arm forwards its console
  # through the app. Every line is stamped on arrival.
  MIGO_CAPI_LOG=error "$(app "$arm")" -BenchGame "$(asset "$game")" -BenchLandscape "$(landscape "$game")" \
    -BenchSettle "$SETTLE" -BenchSeconds 0 2>&1 \
    | perl -MTime::HiRes=time -ne 'BEGIN { $| = 1 } printf "%.3f %s", time, $_' > "$pfx.log" &
  local deadline=$((SECONDS + SETTLE + 60))
  until grep -qs "\[bench\] measuring" "$pfx.log"; do
    if grep -qs "\[bench\] \(failed\|not rendering\|the window is not visible\)" "$pfx.log" || (( SECONDS > deadline )); then
      echo "[macos-ab] $arm/$game round $round: never started measuring:" >&2
      grep "\[bench\]" "$pfx.log" | grep -v "fps=" >&2 || true
      stop_ours || true; return 1
    fi
    sleep 0.25
  done
  local opened
  opened="$(grep -m1 "\[bench\] measuring" "$pfx.log" | cut -d' ' -f1)"
  local main
  main="$(pgrep -x "$(exe "$arm")" | head -1)"
  # The arm: the app, and every WebKit helper running now. None ran before the
  # launch (stop_ours), so each one was started by this app.
  local pids="$main $(webkit_pids | paste -sd' ' -)"
  if [[ "$arm" == migo && "$pids" != "$main " ]]; then
    echo "[macos-ab] migo/$game round $round: WebKit processes appeared during a Migo cell: $pids" >&2
    stop_ours || true; return 1
  fi
  local names="" pid
  for pid in $pids; do names+="$(ps -o comm= -p "$pid" | xargs basename),"; done
  : > "$pfx.cpu0"; : > "$pfx.fp"; : > "$pfx.therm"
  for pid in $pids; do echo "$pid $(cpu_of "$pid")" >> "$pfx.cpu0"; done
  local start=$SECONDS t0
  t0="$(python3 -c 'import time; print(time.time())')"
  while (( SECONDS - start < DUR )); do
    local total=0 v
    for pid in $pids; do v="$(footprint_of "$pid")" || v=0; total="$(python3 -c "print($total + $v)")"; done
    echo "$total" >> "$pfx.fp"
    cpu_limit >> "$pfx.therm"
    sleep 10
  done
  : > "$pfx.cpu1"
  for pid in $pids; do echo "$pid $(cpu_of "$pid" || echo gone)" >> "$pfx.cpu1"; done
  local t1
  t1="$(python3 -c 'import time; print(time.time())')"
  # Still running at the end of the window, or the window measured something else.
  local alive=1
  kill -0 "$main" 2>/dev/null || alive=0
  stop_ours || true
  if (( ! alive )) || grep -q gone "$pfx.cpu1"; then
    echo "[macos-ab] $arm/$game round $round: a process of the arm ended inside the window" >&2
    tail -3 "$pfx.log" >&2; return 1
  fi
  (( round > 0 )) || return 0
  local kv
  kv="$(python3 - "$pfx" "$opened" "$t0" "$t1" "$names" <<'PY'
import re, statistics, sys
pfx, opened, t0, t1, names = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4]), sys.argv[5]
before = dict(line.split() for line in open(pfx + ".cpu0"))
after = dict(line.split() for line in open(pfx + ".cpu1"))
wall = t1 - t0
shares = {pid: (float(after[pid]) - float(before[pid])) / wall * 100 for pid in before}
labels = names.rstrip(",").split(",")
footprints = [float(line) for line in open(pfx + ".fp") if line.strip()]
limits = [int(line) for line in open(pfx + ".therm") if line.strip()]
fps = []
for line in open(pfx + ".log"):
    stamp, _, text = line.partition(" ")
    m = re.search(r"fps=(\d+(?:\.\d+)?)", text)
    if m and opened <= float(stamp) <= opened + (t1 - t0) + 2:
        fps.append(float(m.group(1)))
if not fps:
    sys.exit("no fps telemetry inside the window")
print(f"fps_median={statistics.median(fps):g}")
print(f"fps_min={min(fps):g}")
print(f"cpu_pct={sum(shares.values()):.1f}")
print(f"footprint_mb={statistics.median(footprints):.1f}")
print(f"cpu_limit_min={min(limits) if limits else ''}")
print(f"samples={len(footprints)}")
print("processes=" + " ".join(labels))
print("breakdown=" + " ".join(f"{label}={shares[pid]:.1f}%" for label, pid in zip(labels, before)))
PY
)" || { echo "[macos-ab] $arm/$game round $round: $kv" >&2; return 1; }
  val() { sed -n "s/^$1=//p" <<< "$kv"; }
  echo "$round,$arm,$game,${MODEL%%;*},${MODEL##*;},\"$GPU\",$VERSION,$(val fps_median),$(val fps_min),$(val cpu_pct),$(val footprint_mb),$(val cpu_limit_min),$(val samples),\"$(val processes)\",\"$(val breakdown)\"" >> "$CSV"
  echo "[macos-ab] round $round $arm/$game: fps $(val fps_median) cpu $(val cpu_pct)% footprint $(val footprint_mb) MiB (cpu limit $(val cpu_limit_min))"
}

echo "[macos-ab] $MODEL, GPU $GPU, $VERSION, games='$GAMES', $ROUNDS x ${DUR}s -> $CSV"
FAILED=0
echo "[macos-ab] warm-up (discarded)"
for game in $GAMES; do for arm in $ARMS; do cell 0 "$arm" "$game" || true; done; done
for ((r = 1; r <= ROUNDS; r++)); do
  for game in $GAMES; do
    if (( r % 2 )); then order="$ARMS"; else order="$(tr ' ' '\n' <<< "$ARMS" | tail -r)"; fi
    for arm in $order; do
      cell "$r" "$arm" "$game" || { echo "[macos-ab] round $r $arm/$game FAILED (recorded as missing)"; FAILED=$((FAILED + 1)); }
    done
  done
done
stop_ours || true
rm -rf "$WORK"

python3 - "$CSV" <<'PY'
import csv, statistics, sys
rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["cpu_limit_min"] == "100"]
print("\ngame            arm      n  fps   cpu%    footprint MiB")
for game in dict.fromkeys(r["game"] for r in rows):
    med = {}
    for arm in ("migo", "webview"):
        cells = [r for r in rows if r["game"] == game and r["arm"] == arm]
        if not cells:
            continue
        m = {k: statistics.median(float(r[k]) for r in cells) for k in ("fps_median", "cpu_pct", "footprint_mb")}
        med[arm] = m
        rng = lambda k: f"{min(float(r[k]) for r in cells):g}-{max(float(r[k]) for r in cells):g}"
        print(f"{game:15} {arm:8} {len(cells)}  {m['fps_median']:<4g} {m['cpu_pct']:<6.1f} ({rng('cpu_pct')})  "
              f"{m['footprint_mb']:.1f} ({rng('footprint_mb')})")
    if len(med) == 2:
        print(f"{'':15} migo/webview: cpu {med['migo']['cpu_pct'] / med['webview']['cpu_pct']:.2f}x, "
              f"footprint {med['migo']['footprint_mb'] / med['webview']['footprint_mb']:.2f}x")
PY
# A missing cell is recorded as missing, never retried; the run says so (§10).
(( FAILED == 0 )) || { echo "[macos-ab] $FAILED cell(s) failed" >&2; exit 1; }
