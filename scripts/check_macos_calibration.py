#!/usr/bin/env python3
"""Check a calibration run of scripts/macos-ab.sh against answers fixed in advance.

Usage: check_macos_calibration.py <macos_ab_*.csv>

The same known costs as check_ios_calibration.py, in the same two arms:

  busy   content CPU      8 ms spun per 16.67 ms frame is 48.0% of a core in
                          the process that runs the content -- the app itself
                          on the Migo arm (V8 is in-process), WebKit's
                          WebContent process on the WebView arm -- so it reads
                          at least 48 - 5 and at most 48 + its idle reading + 5.
  mem    footprint        256 MiB written and held: mem - idle is 256, +-10%.
  every cell   fps        >= 57: the spin must not have cost frames, or the
                          48% it is checked against is not what ran.

Medians across rounds. Exits non-zero naming every check that failed.
"""
import csv
import statistics
import sys

SPIN_CPU, CPU_TOLERANCE = 100.0 * 8 / (1000 / 60), 5.0
MEM_MIB, MEM_TOLERANCE = 256.0, 0.10
MIN_FPS = 57
CONTENT_PROCESS = {"migo": "MigoBenchMac", "webview": "com.apple.WebKit.WebContent"}


def process_cpu(row, name):
    """One process's CPU from a row's breakdown (`name=cpu%` ...)."""
    for part in (row.get("breakdown") or "").split():
        process, _, cpu = part.rpartition("=")
        if process == name:
            return float(cpu.rstrip("%"))
    return None


def main():
    rows = list(csv.DictReader(open(sys.argv[1])))
    failures = []
    for arm, content in CONTENT_PROCESS.items():
        def median(game, key):
            cells = [float(r[key]) for r in rows if r["arm"] == arm and r["game"] == game]
            if not cells:
                failures.append(f"{arm}: no {game} cells")
                return None
            return statistics.median(cells)

        def content_cpu(game):
            cells = [process_cpu(r, content) for r in rows if r["arm"] == arm and r["game"] == game]
            cells = [c for c in cells if c is not None]
            if not cells:
                failures.append(f"{arm}: no {content} reading for {game}")
                return None
            return statistics.median(cells)

        idle_cpu, busy_cpu = content_cpu("calib-idle"), content_cpu("calib-busy")
        idle_mem, held_mem = median("calib-idle", "footprint_mb"), median("calib-mem", "footprint_mb")
        if None not in (idle_cpu, busy_cpu):
            low, high = SPIN_CPU - CPU_TOLERANCE, SPIN_CPU + idle_cpu + CPU_TOLERANCE
            ok = low <= busy_cpu <= high
            print(f"{arm:8} busy content CPU {busy_cpu:6.1f}%  expected {low:.1f}..{high:.1f}  "
                  f"{'ok' if ok else 'FAIL'}")
            if not ok:
                failures.append(f"{arm}: busy content CPU {busy_cpu:.1f}%")
        if None not in (idle_mem, held_mem):
            delta = held_mem - idle_mem
            ok = abs(delta - MEM_MIB) <= MEM_TOLERANCE * MEM_MIB
            print(f"{arm:8} mem-idle  MiB  {delta:6.1f}    expected {MEM_MIB:.0f} +-{MEM_TOLERANCE:.0%}  "
                  f"{'ok' if ok else 'FAIL'}")
            if not ok:
                failures.append(f"{arm}: mem-idle footprint {delta:.1f} MiB")
    for r in rows:
        if float(r["fps_median"]) < MIN_FPS:
            failures.append(f"{r['arm']}/{r['game']} round {r['round']}: fps {r['fps_median']}")
    if failures:
        sys.exit("calibration FAILED: " + "; ".join(failures))
    print("calibration: both arms read the known costs")


if __name__ == "__main__":
    main()
