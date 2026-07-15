#!/usr/bin/env bash
# stress-ab.sh <serial> <migo-release-aar> [duration]
#
# Temperature-controlled stress A/B: runs the bunnymark deterministic sprite ramp
# for BOTH webview and migo, each gated to an identical cold start so thermal
# throttling (the dominant confound on this SoC) can't skew the comparison. Per
# second it logs all-three-cluster CPU freq + SoC temp alongside, force-stops
# after each case, and runs each runtime twice. Prints the fps curves at the end.
#
# Why the cold gate: on Kirin 990 the big-cluster thermal cap and the util-driven
# governor make raw fps load- and heat-dependent. Both runtimes must start from the
# same cool state (soc<=35C AND cpu7 scaling_max lifted back to full 2861MHz), and
# the per-cluster freq trace lets you check neither side was throttled at matched
# load. See RESULTS.md 8.
set -eu
S="${1:?usage: stress-ab.sh <serial> <migo-release-aar> [duration]}"
AAR="${2:?need path to a locally-built migo release AAR (scripts/build-aar.sh in the migo repo)}"
DUR="${3:-75}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB=(/home/xg/Android/Sdk/platform-tools/adb -s "$S")
[[ -x "${ADB[0]}" ]] || ADB=(adb -s "$S")
OUT="$DIR/../out"; mkdir -p "$OUT"

read_int() { "${ADB[@]}" shell cat "$1" 2>/dev/null | tr -d '\r\n '; }

cold_gate() {  # <label>
  local label="$1" start soc mx waited
  start=$(date +%s)
  while true; do
    soc=$(read_int /sys/class/thermal/thermal_zone0/temp)
    mx=$(read_int /sys/devices/system/cpu/cpu7/cpufreq/scaling_max_freq)
    waited=$(( $(date +%s) - start ))
    if [[ "${soc:-99999}" -le 35000 && "${mx:-0}" -ge 2861000 ]]; then
      echo "[gate:$label] cold: soc=${soc}mC max=${mx} (waited ${waited}s)"; return
    fi
    [[ "$waited" -ge 420 ]] && { echo "[gate:$label] TIMEOUT ${waited}s soc=${soc}; proceeding"; return; }
    echo "[gate:$label] cooldown soc=${soc}mC (${waited}s)"; sleep 5
  done
}

sample_freq() {  # <outfile> ; background, kill to stop
  echo "epoch_ms,soc_mC,cl2_C,c0cur,c4cur,c4max,c6cur,c6max" > "$1"
  while true; do
    read s t a b c d e < <("${ADB[@]}" shell 'printf "%s %s %s %s %s %s %s\n" \
      "$(cat /sys/class/thermal/thermal_zone0/temp)" \
      "$(cat /sys/class/thermal/thermal_zone5/temp)" \
      "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq)" \
      "$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq)" \
      "$(cat /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq)" \
      "$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq)" \
      "$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_max_freq)"' 2>/dev/null)
    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' "$(date +%s%3N)" "$s" "$t" "$a" "$b" "$c" "$d" "$e" >> "$1"
    sleep 1
  done
}

run_case() {  # <runtime> <pkg> <run_idx>
  local rt="$1" pkg="$2" idx="$3" freqf="$OUT/freq_${1}_r${3}.csv"
  cold_gate "${rt}#${idx}"
  "${ADB[@]}" shell svc power stayon true >/dev/null 2>&1 || true
  "${ADB[@]}" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  sample_freq "$freqf" & local samp=$!
  if [[ "$rt" == migo ]]; then
    bash "$DIR/run.sh" --runtime migo --game bunnymark --device "$S" \
      --scenario stress --duration "$DUR" --migo-aar "local:$AAR"
  else
    bash "$DIR/run.sh" --runtime webview --game bunnymark --device "$S" \
      --scenario stress --duration "$DUR"
  fi
  kill "$samp" 2>/dev/null || true
  "${ADB[@]}" shell am force-stop "$pkg" >/dev/null 2>&1 || true
  cp "$OUT/stress_${rt}.csv" "$OUT/stress_${rt}_r${idx}.csv"
  echo "[case:$rt#$idx] curve -> stress_${rt}_r${idx}.csv  freq -> $(basename "$freqf")"
}

for idx in 1 2; do
  run_case webview com.migo.bench.webview "$idx"
  run_case migo    com.migo.bench.migo    "$idx"
done

echo; echo "=== stress A/B fps curves (out/stress_{runtime}_r{1,2}.csv) ==="
python3 - "$OUT" <<'PY'
import csv, os, sys
o=sys.argv[1]
def load(p): return {int(r['sprites']):int(r['fps_median']) for r in csv.DictReader(open(p))} if os.path.exists(p) else {}
w=[load(f"{o}/stress_webview_r{i}.csv") for i in (1,2)]
m=[load(f"{o}/stress_migo_r{i}.csv") for i in (1,2)]
lv=sorted({n for d in w+m for n in d})
print(f"{'sprites':>8} | {'webview r1/r2':>13} | {'migo r1/r2':>13} | {'migo/wv':>8}")
for n in lv:
    wv=[d.get(n) for d in w]; mo=[d.get(n) for d in m]
    wa=[x for x in wv if x]; ma=[x for x in mo if x]
    r=f"{(sum(ma)/len(ma))/(sum(wa)/len(wa)):.2f}x" if wa and ma else "-"
    fmt=lambda a:'/'.join(str(x) if x is not None else '-' for x in a)
    print(f"{n:>8} | {fmt(wv):>13} | {fmt(mo):>13} | {r:>8}")
PY
