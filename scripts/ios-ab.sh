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
#   (`xcrun devicectl list devices` gives the first id, `xcrun xctrace list devices` the second.)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS="$DIR/../shells/ios"
OUT="$DIR/../out"; mkdir -p "$OUT"
DEVICE=""; UDID=""; VERSION=""; TEAM=""
GAMES="bunnymark endless-runner canvasmark"; ROUNDS=3; DUR=60; SETTLE=8
while [[ $# -gt 0 ]]; do case "$1" in
  --device) DEVICE="$2"; shift 2;;
  --udid) UDID="$2"; shift 2;;
  --version) VERSION="$2"; shift 2;;
  --team) TEAM="$2"; shift 2;;
  --games) GAMES="$2"; shift 2;;
  --rounds) ROUNDS="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done
[[ -n "$DEVICE" && -n "$UDID" && -n "$VERSION" && -n "$TEAM" ]] || {
  echo "ERROR: --device, --udid, --version and --team are required" >&2; exit 2; }

asset() { [[ "$1" == bunnymark ]] && echo game || echo "game-$1"; }
landscape() {
  python3 -c 'import json,sys; print("YES" if json.load(open(sys.argv[1])).get("deviceOrientation") == "landscape" else "NO")' \
    "$DIR/../shells/migo-shell/app/src/main/assets/$(asset "$1")/game.json"
}
bundle() { [[ "$1" == migo ]] && echo com.migo.bench.ios.migo || echo com.migo.bench.ios.webview; }
exe() { [[ "$1" == migo ]] && echo MigoBench || echo WebViewBench; }

# The release's Apple SDK, exactly as published.
if [[ "$(cat "$IOS/.sdk-version" 2>/dev/null)" != "$VERSION" ]]; then
  tmp="$(mktemp -d)"
  gh release download "$VERSION" -R minigame-labs/migo -p "migo-${VERSION#v}-apple-sdk.zip" -D "$tmp"
  unzip -q "$tmp"/*.zip -d "$tmp/u"
  rm -rf "$IOS/sdk" && mv "$tmp/u/MigoApple" "$IOS/sdk" && rm -rf "$tmp"
  echo "$VERSION" > "$IOS/.sdk-version"
fi

# Built and installed once, then left alone (§2).
( cd "$IOS" && BENCH_TEAM="$TEAM" xcodegen generate -q )
for arm in migo webview; do
  xcodebuild -project "$IOS/MigoBenchIOS.xcodeproj" -scheme "$(exe $arm)" -configuration Release \
    -destination "id=$UDID" -derivedDataPath "$IOS/build" -allowProvisioningUpdates -quiet build
  xcrun devicectl device install app --device "$DEVICE" \
    "$IOS/build/Build/Products/Release-iphoneos/$(exe $arm).app" >/dev/null
done

WORK="$(mktemp -d)"
xcrun devicectl device info details --device "$DEVICE" --json-output "$WORK/details.json" >/dev/null
MODEL="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["result"]; print(d["hardwareProperties"]["marketingName"] + ";" + d["deviceProperties"]["osVersionNumber"])' "$WORK/details.json")"
SESSION="$(date -u +%Y%m%dT%H%M%SZ)"
CSV="$OUT/ios_ab_${SESSION}.csv"
echo "round,arm,game,device,ios,migo_version,fps_median,fps_min,cpu_pct,footprint_mb,thermal,samples,processes" > "$CSV"

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

cell() {  # <round> <arm> <game>; round 0 is the warm-up and is not recorded
  local round="$1" arm="$2" game="$3" pfx="$WORK/$1-$2-$3"
  # Thirty idle seconds between cells: iOS exposes no SoC temperature to gate on
  # the way the Android harness does, so the gate is a fixed rest plus the
  # thermal state recorded with every cell.
  stop_ours; sleep 30
  xcrun devicectl device process launch --device "$DEVICE" --terminate-existing --console "$(bundle "$arm")" -- \
    -BenchGame "$(asset "$game")" -BenchLandscape "$(landscape "$game")" \
    -BenchSettle "$SETTLE" -BenchSeconds "$((DUR + 3))" > "$pfx.log" 2>&1 &
  local app=$!
  local waited=0
  until grep -qs "\[bench\] measuring" "$pfx.log"; do
    if ! kill -0 "$app" 2>/dev/null || (( waited > SETTLE + 60 )); then
      echo "[ios-ab] $arm/$game round $round: never started measuring:" >&2
      grep "\[bench\]" "$pfx.log" | grep -v "fps=" >&2 || true
      kill "$app" 2>/dev/null || true
      return 1
    fi
    sleep 0.5; waited=$((waited + 1))
  done
  rm -rf "$pfx.trace"
  xcrun xctrace record --device "$UDID" --template 'Activity Monitor' --all-processes \
    --time-limit "${DUR}s" --output "$pfx.trace" >/dev/null 2>&1
  wait "$app" || { echo "[ios-ab] $arm/$game round $round: the app failed" >&2; tail -3 "$pfx.log" >&2; return 1; }
  (( round > 0 )) || return 0
  for t in sysmon-process device-thermal-state-intervals; do
    xcrun xctrace export --input "$pfx.trace" \
      --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$t\"]" > "$pfx.$t.xml"
  done
  local kv
  kv="$(python3 "$DIR/ios_trace.py" "$pfx.sysmon-process.xml" "$pfx.device-thermal-state-intervals.xml" \
    "$pfx.log" "$(exe "$arm")")" || return 1
  val() { sed -n "s/^$1=//p" <<< "$kv"; }
  echo "$round,$arm,$game,${MODEL%%;*},${MODEL##*;},$VERSION,$(val fps_median),$(val fps_min),$(val cpu_pct),$(val footprint_mb),$(val thermal),$(val samples),\"$(val processes)\"" >> "$CSV"
  echo "[ios-ab] round $round $arm/$game: fps $(val fps_median) cpu $(val cpu_pct)% footprint $(val footprint_mb) MiB ($(val thermal))"
}

echo "[ios-ab] $MODEL, $VERSION, games='$GAMES', $ROUNDS x ${DUR}s -> $CSV"
FAILED=0
echo "[ios-ab] warm-up (discarded)"
for game in $GAMES; do for arm in migo webview; do cell 0 "$arm" "$game" || true; done; done
for ((r = 1; r <= ROUNDS; r++)); do
  for game in $GAMES; do
    if (( r % 2 )); then order="migo webview"; else order="webview migo"; fi
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
