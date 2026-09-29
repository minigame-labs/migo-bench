#!/usr/bin/env bash
# iOS: Migo against WKWebView -- same release, same game, same iPhone, one session.
#
# The Android matrix's question asked on iOS. Both arms run their content JS in
# WebKit's WebContent process with the same JavaScriptCore JIT (Migo's iOS
# product, Performance+, puts it there and renders natively), so fps is not the
# difference being looked for; what the harness reads is the CPU and memory it
# costs to get there. Steady state only: no startup numbers (the arms have no
# common "game ready" event -- MEASURING.md §6).
#
#   arm migo     shells/ios MigoBench: migo-shell's game package in a
#                MigoGameView, linked against the release's Apple SDK
#   arm webview  shells/ios WebViewBench: webview-shell's page in a WKWebView
#
# Per cell: launch the arm; the app itself proves after the settle that it is
# active and drawing (Bench.swift) and prints `[bench] measuring`; the device is
# then recorded with Instruments' Activity Monitor for the window. An arm is its
# app process plus the WebKit helpers it started (scripts/ios_trace.py) -- the
# Android harness's "count the WebView renderer" rule, applied to both arms.
# Rounds interleave and alternate order (§3); every cell records the thermal
# states the device reported, and a cell that was not Nominal throughout is kept
# in the CSV but left out of the summary.
#
# Runs on a Mac with Xcode, XcodeGen and an authenticated gh. The iPhone must be
# unlocked with Auto-Lock set to Never: a locked phone keeps the app inactive,
# and the apps refuse to measure then.
#
# Usage:
#   ios-ab.sh --device <CoreDevice id> --udid <hardware UDID> --version vX.Y.Z --team <TEAM>
#             [--games "bunnymark endless-runner canvasmark"] [--rounds 3] [--duration 60]
#             [--arms "migo webview"]
#   `--arms migo` measures one arm alone: for comparing two builds of Migo while
#   working on it, never for a Migo-against-WebView figure.
#   (`xcrun devicectl list devices` gives the first id, `xcrun xctrace list devices` the second.)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS="$DIR/../shells/ios"
OUT="$DIR/../out"; mkdir -p "$OUT"
DEVICE=""; UDID=""; VERSION=""; TEAM=""
GAMES="bunnymark endless-runner canvasmark"; ROUNDS=3; DUR=60; SETTLE=8; ARMS="migo webview"
while [[ $# -gt 0 ]]; do case "$1" in
  --device) DEVICE="$2"; shift 2;;
  --udid) UDID="$2"; shift 2;;
  --version) VERSION="$2"; shift 2;;
  --team) TEAM="$2"; shift 2;;
  --games) GAMES="$2"; shift 2;;
  --arms) ARMS="$2"; shift 2;;
  --rounds) ROUNDS="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done
[[ -n "$DEVICE" && -n "$UDID" && -n "$VERSION" && -n "$TEAM" ]] || {
  echo "ERROR: --device, --udid, --version and --team are required" >&2; exit 2; }

# A game's bundle resource, and where its game.json is. `calib-*` are the
# measurement calibration packages (shells/ios/calibration), shared by both
# arms; scripts/ios-validate-measurement.sh runs them.
asset() {
  case "$1" in
    bunnymark) echo game ;;
    calib-*) echo "$1" ;;
    *) echo "game-$1" ;;
  esac
}
landscape() {
  local manifest="$DIR/../shells/migo-shell/app/src/main/assets/$(asset "$1")/game.json"
  [[ "$1" == calib-* ]] && manifest="$IOS/calibration/$1/game.json"
  python3 -c 'import json,sys; print("YES" if json.load(open(sys.argv[1])).get("deviceOrientation") == "landscape" else "NO")' \
    "$manifest"
}
bundle() { [[ "$1" == migo ]] && echo com.migo.bench.ios.migo || echo com.migo.bench.ios.webview; }
exe() { [[ "$1" == migo ]] && echo MigoBench || echo WebViewBench; }

# The release's Apple SDK, exactly as published.
if [[ "$(cat "$IOS/.sdk-version" 2>/dev/null)" != "$VERSION" ]]; then
  tmp="$(mktemp -d)"
  gh release download "$VERSION" -R minigame-labs/migo-runtime -p "migo-${VERSION#v}-apple-sdk.zip" -D "$tmp"
  unzip -q "$tmp"/*.zip -d "$tmp/u"
  rm -rf "$IOS/sdk" && mv "$tmp/u/MigoApple" "$IOS/sdk" && rm -rf "$tmp"
  echo "$VERSION" > "$IOS/.sdk-version"
fi

# Built and installed once, then left alone (§2). Derived data is kept per SDK
# version: Swift's precompiled modules of one SDK's headers are otherwise reused
# against another's, and the build fails on symbols the other never had.
( cd "$IOS" && BENCH_TEAM="$TEAM" xcodegen generate -q )
for arm in $ARMS; do
  xcodebuild -project "$IOS/MigoBenchIOS.xcodeproj" -scheme "$(exe $arm)" -configuration Release \
    -destination "id=$UDID" -derivedDataPath "$IOS/build/$VERSION" -allowProvisioningUpdates -quiet build
  xcrun devicectl device install app --device "$DEVICE" \
    "$IOS/build/$VERSION/Build/Products/Release-iphoneos/$(exe $arm).app" >/dev/null
done

WORK="$(mktemp -d)"
xcrun devicectl device info details --device "$DEVICE" --json-output "$WORK/details.json" >/dev/null
MODEL="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["result"]; print(d["hardwareProperties"]["marketingName"] + ";" + d["deviceProperties"]["osVersionNumber"])' "$WORK/details.json")"
SESSION="$(date -u +%Y%m%dT%H%M%SZ)"
CSV="$OUT/ios_ab_${SESSION}.csv"
echo "round,arm,game,device,ios,migo_version,fps_median,fps_min,cpu_pct,footprint_mb,thermal,samples,processes,breakdown" > "$CSV"

# Our own apps only: a bench or Migo app left running holds WebKit helpers. Other
# apps on the phone are not ours to stop; ios_trace.py fails a cell whose WebKit
# helpers are ambiguous instead.
stop_ours() {
  xcrun devicectl device info processes --device "$DEVICE" --json-output "$WORK/procs.json" >/dev/null 2>&1
  python3 - "$WORK/procs.json" <<'PY' | while read -r pid; do
import json, sys
for p in json.load(open(sys.argv[1]))["result"]["runningProcesses"]:
    exe = p.get("executable", "")
    if "/Bundle/Application/" in exe and exe.rsplit("/", 1)[-1] in ("MigoBench", "WebViewBench", "MigoExample", "MigoDeviceTestHost", "MigoProbe"):
        print(p["processIdentifier"])
PY
    xcrun devicectl device process terminate --device "$DEVICE" --pid "$pid" >/dev/null 2>&1 || true
  done
}

# Read one table out of a saved trace.
#
# `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1` is load-bearing. Building a trace's
# table of contents, xctrace (Xcode 26.5) loads every recorded process's images
# in parallel on the Swift-concurrency pool, and one of those jobs over-releases
# an object: SIGSEGV in objc_release under ProcessLoader.load(), on 60-80% of
# exports of the same file, worse on a loaded Mac. The variable narrows that pool
# to one thread, which removes the race: 30 of 30 exports then succeeded, with
# the table bytes identical to the exports that had survived the race. So an
# export that still fails is a real failure and is reported, not retried.
export_table() {  # <trace> <xpath or /trace-toc> <out>
  local status=0
  if [[ "$2" == /trace-toc ]]; then
    LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 xcrun xctrace export --input "$1" --toc > "$3" 2> "$3.err" || status=$?
  else
    LIBDISPATCH_COOPERATIVE_POOL_STRICT=1 xcrun xctrace export --input "$1" --xpath "$2" > "$3" 2> "$3.err" || status=$?
  fi
  if (( status != 0 )) || [[ ! -s "$3" ]]; then
    echo "[ios-ab] xctrace export of $2 failed (exit $status): $1" >&2
    tail -3 "$3.err" >&2
    return 1
  fi
}

cell() {  # <round> <arm> <game>; round 0 is the warm-up and is not recorded
  local round="$1" arm="$2" game="$3" pfx="$WORK/$1-$2-$3"
  # Thirty idle seconds between cells: iOS exposes no SoC temperature to gate on
  # the way the Android harness does, so the gate is a fixed rest plus the
  # thermal state recorded with every cell.
  stop_ours; sleep 30
  # The recording starts first, with the home screen in front, and the game is
  # launched into it. Started with a landscape app already in front, Instruments
  # took ~35 s to begin and then lost the device ("Device got disconnected") on
  # every landscape cell, both arms; started first, it records through the
  # rotation. The cap only bounds a stuck cell: the recording is stopped (SIGINT,
  # which saves it) once the window has passed.
  rm -rf "$pfx.trace"
  xcrun xctrace record --device "$UDID" --template 'Activity Monitor' --all-processes \
    --time-limit "$((SETTLE + DUR + 240))s" --output "$pfx.trace" > "$pfx.record.log" 2>&1 &
  local recorder=$!
  local deadline=$((SECONDS + 120))
  until grep -qs "Starting recording" "$pfx.record.log"; do
    if ! kill -0 "$recorder" 2>/dev/null || (( SECONDS > deadline )); then
      echo "[ios-ab] $arm/$game round $round: the recording did not start:" >&2
      tail -3 "$pfx.record.log" >&2; kill "$recorder" 2>/dev/null; return 1
    fi
    sleep 0.5
  done
  # The app runs until this ends it (`-BenchSeconds 0`). Every console line is
  # stamped on arrival: `measuring` opens the window, and only the samples and
  # fps lines inside it are counted.
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console "$(bundle "$arm")" -- \
    -BenchGame "$(asset "$game")" -BenchLandscape "$(landscape "$game")" \
    -BenchSettle "$SETTLE" -BenchSeconds 0 2>&1 \
    | perl -MTime::HiRes=time -ne 'BEGIN { $| = 1 } printf "%.3f %s", time, $_' > "$pfx.log" &
  local app=$!
  # Launching can itself take ~40 s (a portrait app after a landscape one), then
  # the settle; two minutes past the settle is a stuck launch, not a slow one.
  deadline=$((SECONDS + SETTLE + 120))
  until grep -qs "\[bench\] measuring" "$pfx.log"; do
    if ! kill -0 "$app" 2>/dev/null || (( SECONDS > deadline )); then
      echo "[ios-ab] $arm/$game round $round: never started measuring:" >&2
      grep "\[bench\]" "$pfx.log" | grep -v "fps=" >&2 || true
      kill "$app" 2>/dev/null; kill -INT "$recorder" 2>/dev/null; wait "$recorder"; stop_ours
      return 1
    fi
    sleep 0.5
  done
  local opened
  opened="$(grep -m1 "\[bench\] measuring" "$pfx.log" | cut -d' ' -f1)"
  sleep "$((DUR + 2))"
  # Still running when the window closed, or the window measured something else.
  local alive=1
  kill -0 "$app" 2>/dev/null || alive=0
  kill -INT "$recorder" 2>/dev/null; wait "$recorder"
  stop_ours; wait "$app" 2>/dev/null || true
  if (( ! alive )); then
    echo "[ios-ab] $arm/$game round $round: the app ended inside the window:" >&2
    tail -3 "$pfx.log" >&2; return 1
  fi
  if grep -qs "\[bench\] restarted" "$pfx.log"; then
    echo "[ios-ab] $arm/$game round $round: WebKit's content process died inside the cell and the game restarted" >&2
    return 1
  fi
  (( round > 0 )) || return 0
  export_table "$pfx.trace" "/trace-toc" "$pfx.toc.xml" || return 1
  for t in sysmon-process device-thermal-state-intervals; do
    export_table "$pfx.trace" "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$t\"]" "$pfx.$t.xml" || return 1
  done
  local kv
  kv="$(python3 "$DIR/ios_trace.py" "$pfx.toc.xml" "$opened" "$DUR" "$pfx.sysmon-process.xml" \
    "$pfx.device-thermal-state-intervals.xml" "$pfx.log" "$(exe "$arm")")" || return 1
  val() { sed -n "s/^$1=//p" <<< "$kv"; }
  echo "$round,$arm,$game,${MODEL%%;*},${MODEL##*;},$VERSION,$(val fps_median),$(val fps_min),$(val cpu_pct),$(val footprint_mb),$(val thermal),$(val samples),\"$(val processes)\",\"$(val breakdown)\"" >> "$CSV"
  echo "[ios-ab] round $round $arm/$game: fps $(val fps_median) cpu $(val cpu_pct)% footprint $(val footprint_mb) MiB ($(val thermal))"
}

echo "[ios-ab] $MODEL, $VERSION, games='$GAMES', $ROUNDS x ${DUR}s -> $CSV"
FAILED=0
echo "[ios-ab] warm-up (discarded)"
for game in $GAMES; do for arm in $ARMS; do cell 0 "$arm" "$game" || true; done; done
for ((r = 1; r <= ROUNDS; r++)); do
  for game in $GAMES; do
    # Alternate which arm goes first (§3); one arm alone has no order to alternate.
    if (( r % 2 )); then order="$ARMS"; else order="$(tr ' ' '\n' <<< "$ARMS" | tail -r 2>/dev/null || tr ' ' '\n' <<< "$ARMS" | tac)"; fi
    for arm in $order; do
      cell "$r" "$arm" "$game" || { echo "[ios-ab] round $r $arm/$game FAILED (recorded as missing)"; FAILED=$((FAILED + 1)); }
    done
  done
done
stop_ours
rm -rf "$WORK"

python3 - "$CSV" <<'PY'
import csv, statistics, sys
rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["thermal"] == "Nominal"]
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
(( FAILED == 0 )) || { echo "[ios-ab] $FAILED cell(s) failed" >&2; exit 1; }
