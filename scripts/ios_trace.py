#!/usr/bin/env python3
"""Reduce one iOS cell -- an xctrace Activity Monitor recording and the app's
console -- to its numbers.

Usage: ios_trace.py <sysmon-process.xml> <thermal.xml> <console.log> <app process name>

The XML files are `xctrace export`s of the `sysmon-process` and
`device-thermal-state-intervals` tables. One arm is its app
process plus every WebKit helper (`com.apple.WebKit.*`) with a higher pid: the
Migo arm's content runs in WebKit's WebContent process, and the baseline's page
does, so leaving the helpers out would undercount both -- the Android harness's
"count the WebView renderer" rule. iOS reports no responsible pid (every row
says 1). Helpers of apps that were already running have lower pids than the app
just launched; one another app starts during the cell would be a second helper
of its kind, which fails the cell rather than be guessed at. The processes
counted are printed so a row can be audited.

Prints key=value lines:
  fps_median    median of the game's own fps=N lines after `[bench] measuring`
  fps_min       the lowest of them
  thermal       every thermal state the device reported during the recording
  cpu_pct       CPU time the arm used over the window, as % of one core
  footprint_mb  median over samples of the arm's summed physical footprint
                (the figure iOS's memory limit acts on), in MiB
  samples       sampling instants in the window
  processes     name(pid) of everything counted
"""
import re
import statistics
import sys
import xml.etree.ElementTree as ET


def table(path):
    root = ET.parse(path).getroot()
    cols = [c.findtext("mnemonic") for c in root.iter("col")]
    by_id = {e.attrib["id"]: e for e in root.iter() if "id" in e.attrib}

    def resolve(e):
        return by_id[e.attrib["ref"]] if "ref" in e.attrib else e

    return [dict(zip(cols, (resolve(e) for e in row))) for row in root.iter("row")]


def fps_lines(path):
    """The fps telemetry printed after the measurement window opened."""
    values, measuring = [], False
    with open(path, errors="replace") as log:
        for line in log:
            if "[bench] measuring" in line:
                measuring = True
            elif measuring and (m := re.search(r"\bfps=(\d+)", line)):
                values.append(int(m.group(1)))
    return values


def main():
    sysmon, thermal, console, app = sys.argv[1:5]
    fps = fps_lines(console)
    if len(fps) < 3:
        sys.exit(f"ios_trace: {len(fps)} fps lines in the window; the game's telemetry did not run")
    print(f"fps_median={statistics.median(fps):g}")
    print(f"fps_min={min(fps)}")
    states = sorted({row["thermal-state"].text for row in table(thermal)})
    print("thermal=" + "+".join(states))
    rows = []
    for cell in table(sysmon):
        name = cell["process"].attrib.get("fmt", "").rsplit(" (", 1)[0]
        rows.append((
            int(cell["time"].text),
            name,
            int(cell["pid"].text),
            int(cell["cpu-total-user"].text or 0) + int(cell["cpu-total-system"].text or 0),
            int(cell["memory-physical-footprint"].text or 0),
        ))

    app_pids = {pid for _, name, pid, _, _ in rows if name == app}
    if len(app_pids) != 1:
        sys.exit(f"ios_trace: expected one {app} process in the recording, found {sorted(app_pids)}")
    app_pid = app_pids.pop()
    counted = {(name, pid) for _, name, pid, _, _ in rows
               if pid == app_pid or (name.startswith("com.apple.WebKit.") and pid > app_pid)}
    helpers = [name for name, _ in counted if name != app]
    if len(helpers) != len(set(helpers)):
        sys.exit("ios_trace: two WebKit helpers of one kind above the app's pid -- another app "
                 f"started WebKit during the cell, so which are this arm's is ambiguous: {sorted(counted)}")
    pids = {pid for _, pid in counted}

    footprint_at = {}
    cpu_span = {}
    for time, name, pid, cpu, footprint in rows:
        if pid not in pids:
            continue
        footprint_at[time] = footprint_at.get(time, 0) + footprint
        first, last = cpu_span.get(pid, ((time, cpu), (time, cpu)))
        cpu_span[pid] = (min(first, (time, cpu)), max(last, (time, cpu)))

    times = sorted(footprint_at)
    window_ns = times[-1] - times[0]
    if len(times) < 3 or window_ns <= 0:
        sys.exit(f"ios_trace: too few samples ({len(times)})")
    cpu_ns = sum(last[1] - first[1] for first, last in cpu_span.values())
    print(f"cpu_pct={100.0 * cpu_ns / window_ns:.1f}")
    print(f"footprint_mb={statistics.median(footprint_at[t] for t in times) / 2**20:.1f}")
    print(f"samples={len(times)}")
    print("processes=" + ",".join(f"{n}({p})" for n, p in sorted(counted, key=lambda c: c[1])))


if __name__ == "__main__":
    main()
