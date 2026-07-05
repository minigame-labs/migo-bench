#!/usr/bin/env python3
"""Build an fps-vs-load curve from a `bunnies=N fps=M` telemetry stream.

Reads the stream on stdin, groups fps samples by sprite count N (the deterministic
in-game ramp steps), prints `runtime,sprites,fps_median` rows, and reports the
"knee" (max sprites still holding >= threshold fps) on stderr.

Usage:  stress_curve.py <runtime> [fps_threshold=55] < stream.txt
"""
import re
import statistics
import sys
from collections import defaultdict


def main() -> None:
    runtime = sys.argv[1] if len(sys.argv) > 1 else ""
    thresh = int(sys.argv[2]) if len(sys.argv) > 2 else 55
    by_n = defaultdict(list)
    for line in sys.stdin:
        m = re.search(r"bunnies=(\d+) fps=(\d+)", line)
        if m:
            by_n[int(m.group(1))].append(int(m.group(2)))
    rows = [(n, round(statistics.median(v))) for n, v in sorted(by_n.items())]
    print("runtime,sprites,fps_median")
    for n, f in rows:
        print(f"{runtime},{n},{f}")
    knee = max((n for n, f in rows if f >= thresh), default=0)
    print(f"[stress] {runtime}: knee(>= {thresh}fps) = {knee} sprites "
          f"(over {len(rows)} load levels)", file=sys.stderr)


if __name__ == "__main__":
    main()
