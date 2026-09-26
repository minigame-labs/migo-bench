#!/usr/bin/env python3
"""Reduce one iOS cell -- an xctrace Activity Monitor recording and the app's
console -- to its numbers.

Usage: ios_trace.py <toc.xml> <window opened> <seconds> <sysmon-process.xml> <thermal.xml>
                    <console.log> <app process name>

The XML files are `xctrace export`s of the trace's table of contents and of
its `sysmon-process` and `device-thermal-state-intervals` tables; the console
log is the app's, each line stamped with the Unix time it arrived.

The window is <seconds> from <window opened> (the Unix time `[bench] measuring`
arrived). The recording must cover all of it -- Instruments can end a recording
early without an error -- and only the samples, thermal intervals and fps lines
inside it are counted. Sample times are the recording's own offsets, placed on
the wall clock by the recording's start date.

One arm is its app
process plus every WebKit helper (`com.apple.WebKit.*`) with a higher pid: the
Migo arm's content runs in WebKit's WebContent process, and the baseline's page
does, so leaving the helpers out would undercount both -- the Android harness's
"count the WebView renderer" rule. iOS reports no responsible pid (every row
says 1). Helpers of apps that were already running have lower pids than the app
just launched; one another app starts during the cell would be a second helper
of its kind, which fails the cell rather than be guessed at. The processes
counted are printed so a row can be audited.

Prints key=value lines:
  fps_median    median of the game's own fps=N lines inside the window
  fps_min       the lowest of them
  thermal       every thermal state the device reported during the window
  cpu_pct       CPU time the arm used over the window, as % of one core
  footprint_mb  median over samples of the arm's summed physical footprint
                (the figure iOS's memory limit acts on), in MiB
  samples       sampling instants in the window
  processes     name(pid) of everything counted
"""
import datetime
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


def window(toc_path):
    """The recording's start and end, as Unix times."""
    run = ET.parse(toc_path).getroot().find("run")
    start, end = (datetime.datetime.fromisoformat(run.findtext(f"info/summary/{tag}")).timestamp()
                  for tag in ("start-date", "end-date"))
    return start, end


def fps_lines(path, start, end):
    """The fps telemetry stamped inside the recording."""
    values = []
    with open(path, errors="replace") as log:
        for line in log:
            stamp, _, text = line.partition(" ")
            m = re.search(r"\bfps=(\d+)", text)
            if m and start <= float(stamp) <= end:
                values.append(int(m.group(1)))
    return values


def main():
    toc, opened, seconds, sysmon, thermal, console, app = sys.argv[1:8]
    start, end = window(toc)
    lo, hi = float(opened), float(opened) + float(seconds)
    # One sampling interval of slack at the end: the last sample can land just
    # short of the window's close.
    if start > lo or end < hi - 1.0:
        sys.exit(f"ios_trace: the recording ({start:.1f}-{end:.1f}) does not cover the window "
                 f"({lo:.1f}-{hi:.1f})")
    fps = fps_lines(console, lo, hi)
    # The telemetry prints once a second; most of the window must be covered.
    if len(fps) < 0.8 * (hi - lo):
        sys.exit(f"ios_trace: {len(fps)} fps lines in a {hi - lo:.0f} s window; "
                 "the game's telemetry did not run through it")
    print(f"fps_median={statistics.median(fps):g}")
    print(f"fps_min={min(fps)}")
    at = lambda offset_ns: start + int(offset_ns) / 1e9
    states = sorted({row["thermal-state"].text for row in table(thermal)
                     if at(row["start"].text) < hi and at(row["end"].text) > lo})
    print("thermal=" + "+".join(states))
    rows = []
    for cell in table(sysmon):
        if not lo <= at(cell["time"].text) <= hi:
            continue
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
