#!/usr/bin/env python3
"""Parse `dumpsys SurfaceFlinger --latency <layer>` on stdin -> per-frame fps, one per line.

Format: line 1 = refresh period (ns); each following line = three tab-separated ns
timestamps (desiredPresent, actualPresent, frameReady). Rows of zeros / MAX are
pending/invalid and are skipped. fps for a frame = 1e9 / (actualPresent[i] - actualPresent[i-1]).
"""
import sys

MAXV = 9.2e18


def main() -> None:
    ts = []
    for i, line in enumerate(sys.stdin):
        if i == 0:  # refresh-period header
            continue
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            actual = int(parts[1])
        except ValueError:
            continue
        if 0 < actual < MAXV:
            ts.append(actual)
    ts.sort()
    for a, b in zip(ts, ts[1:]):
        d = b - a
        if 0 < d < 10**9:  # ignore <=0 and >1s gaps
            print(f"{1e9 / d:.1f}")


if __name__ == "__main__":
    main()
