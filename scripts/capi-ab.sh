#!/usr/bin/env bash
# The C ABI against the Java SDK: same engine release, same game, one session.
#
# migo's C ABI cannot be declared stable while one freeze blocker is open:
# "Android performance with no material regression" (include/migo/README.md).
# The Java SDK is what every Android host embeds today, so it is the baseline,
# and this is the within-session A/B that MEASURING.md §3/§4b says is the only
# comparison this repository can make.
#
#   arm java  the migo shell with a release AAR          (run.sh --runtime migo)
#   arm capi  migo's NativeActivity C host, linked       (run.sh --runtime capi)
#             against the same release's capi package
#
# Steady state only -- fps, CPU, PSS -- for the reason capture-capi.sh gives:
# neither the startup event nor its noise floor would be comparable.
#
# The verdict is fixed here, before any number exists, so it cannot be fitted
# to one. Against the java arm's median, capi fails if fps drops below 97%, or
# CPU or PSS rises above 105%. Those bands are wider than the harness's own
# steady-state noise (§4b: CPU and PSS within 1-2% of themselves) and far
# tighter than any difference that would matter to a host.
#
# Usage:
#   capi-ab.sh --device SERIAL --aar PATH --capi-apk PATH --version TAG
#              [--games "bunnymark endless-runner"] [--rounds 3] [--duration 60]
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$DIR/../out"; mkdir -p "$OUT"
SERIAL=""; AAR=""; APK=""; VERSION=""
GAMES="bunnymark endless-runner"; ROUNDS=3; DUR=60
while [[ $# -gt 0 ]]; do case "$1" in
  --device) SERIAL="$2"; shift 2;;
  --aar) AAR="$2"; shift 2;;
  --capi-apk) APK="$2"; shift 2;;
  --version) VERSION="$2"; shift 2;;
  --games) GAMES="$2"; shift 2;;
  --rounds) ROUNDS="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;;
  *) echo "unknown arg: $1" >&2; exit 2;;
esac; done
[[ -n "$SERIAL" && -f "$AAR" && -f "$APK" && -n "$VERSION" ]] || {
  echo "ERROR: --device, --aar (file), --capi-apk (file) and --version are required" >&2; exit 2; }

ADB_BIN="${ANDROID_HOME:+$ANDROID_HOME/platform-tools/adb}"
[[ -n "$ADB_BIN" && -x "$ADB_BIN" ]] || ADB_BIN="$HOME/Android/Sdk/platform-tools/adb"
[[ -x "$ADB_BIN" ]] || ADB_BIN="adb"
ADB=("$ADB_BIN" -s "$SERIAL")
SERIAL="$SERIAL" . "$DIR/lib.sh"
export CAPI_APK="$APK" CAPI_VERSION="$VERSION"

SESSION="$(date -u +%Y%m%dT%H%M%SZ)"
AB="$OUT/capi_ab_${SESSION}.csv"
{ printf 'round,arm,gate,'; python3 "$DIR/parse.py" --header-only; } > "$AB"
[[ -f "$OUT/results.csv" ]] || python3 "$DIR/parse.py" --header-only > "$OUT/results.csv"

stop_both() {
  "${ADB[@]}" shell am force-stop com.migo.bench.migo >/dev/null 2>&1 || true
  "${ADB[@]}" shell am force-stop com.migo.chost >/dev/null 2>&1 || true
}

one_cell() {  # <round> <game> <arm> -> appends a row to $AB, or says why not
  local round="$1" game="$2" arm="$3" runtime before after log
  runtime=migo; [[ "$arm" == capi ]] && runtime=capi
  log="$OUT/capi_ab_${SESSION}_${round}_${game}_${arm}.log"
  stop_both
  local gate; gate="$(cold_gate "r${round}/${game}/${arm}")"
  echo "[capi-ab]   gate: $gate"
  case "$gate" in TIMEOUT*) echo "[capi-ab]   WARNING: this row is not temperature-gated";; esac
  before="$(wc -l < "$OUT/results.csv")"
  bash "$DIR/run.sh" --runtime "$runtime" --game "$game" --device "$SERIAL" \
    --migo-aar "local:$AAR" --duration "$DUR" --cold-runs 1 >"$log" 2>&1 || {
      echo "[capi-ab]   RUN FAILED -- see $log" >&2; return 1; }
  after="$(wc -l < "$OUT/results.csv")"
  (( after > before )) || { echo "[capi-ab]   run appended no row -- see $log" >&2; return 1; }
  # These rows are an A/B, not the published steady-state table: move them out.
  [[ "$round" == warmup ]] || \
    printf '%s,%s,"%s",%s\n' "$round" "$arm" "$gate" "$(tail -1 "$OUT/results.csv")" >> "$AB"
  sed -i '$d' "$OUT/results.csv"
}

echo "[capi-ab] device=$SERIAL version=$VERSION rounds=$ROUNDS games='$GAMES' duration=${DUR}s"
echo "[capi-ab] aar=$AAR"
echo "[capi-ab] apk=$APK"

# §1: neither side is measured on its first launch after an install.
echo "[capi-ab] warm-up (discarded)"
for game in $GAMES; do
  for arm in java capi; do one_cell warmup "$game" "$arm" || exit 1; done
done

for (( round=1; round<=ROUNDS; round++ )); do
  # Alternate which arm goes first, so drift across a round lands on both.
  if (( round % 2 == 1 )); then arms=(java capi); else arms=(capi java); fi
  for game in $GAMES; do
    for arm in "${arms[@]}"; do
      echo "[capi-ab] round $round | $game | $arm"
      one_cell "$round" "$game" "$arm" || exit 1
    done
  done
done
stop_both

python3 - "$AB" <<'PY'
import csv, statistics, sys
rows = list(csv.DictReader(open(sys.argv[1])))
games = sorted({r["game"] for r in rows})
failed = False
def med(game, arm, key):
    vals = [float(r[key]) for r in rows if r["game"] == game and r["arm"] == arm and r[key]]
    return statistics.median(vals), vals
print("game            metric      java (runs)                 capi (runs)                 capi/java  verdict")
for game in games:
    for key, bound, worse_if in (("fps_median", 0.97, "lower"), ("cpu_pct", 1.05, "higher"),
                                 ("pss_peak_kb", 1.05, "higher")):
        (j, jv), (c, cv) = med(game, "java", key), med(game, "capi", key)
        ratio = c / j if j else float("nan")
        bad = ratio < bound if worse_if == "lower" else ratio > bound
        failed |= bad
        print(f"{game:15} {key:11} {j:9.1f} {str(jv):18} {c:9.1f} {str(cv):18} {ratio:8.3f}  "
              f"{'REGRESSION' if bad else 'ok'}")
print("VERDICT:", "material regression" if failed else "no material regression")
sys.exit(1 if failed else 0)
PY
