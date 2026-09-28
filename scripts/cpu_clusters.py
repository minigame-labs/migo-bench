#!/usr/bin/env python3
"""CPU time by cluster, and the cycles it bought, from two snapshots of every
thread's /proc/<pid>/task/<tid>/time_in_state.

Usage: cpu_clusters.py <before> <after> <clk_tck> <window_s>

Why. CPU time alone says how long cores were busy, not how much work they did:
on a big/mid/little SoC the same work reads several times longer on a little
core at a low clock (MEASURING.md §14). This splits the time by cluster -- each
named by its first CPU, as the kernel's file names it (`cpu0`, `cpu4`, `cpu6`) --
and weights it by the clock it ran at, which is what a frequency-independent
comparison needs.

Snapshot format (lib.sh `_cluster_snapshot`): `T <pid> <tid> <utime+stime>`
opening each thread, then that thread's time_in_state: a `cpuN` line starting a
cluster and `<kHz> <ticks>` lines under it.

Prints key=value lines:
  cpu_<cluster>_pct   that cluster's busy time over the window, % of one core
  gcycles_per_s       sum over clusters and clocks of time x frequency, GHz
  cluster_check       the time_in_state total against the same threads' own
                      utime+stime delta; `ok` within 5%, else the gap
Threads alive at both snapshots only: one that started or ended inside the
window has no delta, which the check makes visible if it mattered.
"""
import collections
import sys


def read(path):
    threads = {}
    current = cluster = None
    for line in open(path):
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "T":
            current = (parts[1], parts[2])
            threads[current] = {"stat": int(parts[3]), "states": collections.Counter()}
        elif parts[0].startswith("cpu"):
            cluster = parts[0]
        elif current is not None and cluster is not None and len(parts) == 2:
            threads[current]["states"][(cluster, int(parts[0]))] += int(parts[1])
    return threads


def main():
    before, after = read(sys.argv[1]), read(sys.argv[2])
    clk, window = float(sys.argv[3]), float(sys.argv[4])
    by_cluster = collections.Counter()
    cycles = 0.0
    state_ticks = stat_ticks = 0
    for key in before.keys() & after.keys():
        stat_ticks += after[key]["stat"] - before[key]["stat"]
        for state, ticks in after[key]["states"].items():
            delta = ticks - before[key]["states"].get(state, 0)
            if delta <= 0:
                continue
            cluster, khz = state
            by_cluster[cluster] += delta
            state_ticks += delta
            cycles += delta / clk * khz * 1e3
    for cluster in sorted(by_cluster, key=lambda c: int(c[3:])):
        print(f"cpu_{cluster}_pct={100.0 * by_cluster[cluster] / clk / window:.1f}")
    print(f"gcycles_per_s={cycles / window / 1e9:.3f}")
    gap = (state_ticks - stat_ticks) / stat_ticks if stat_ticks else 0.0
    print("cluster_check=" + ("ok" if abs(gap) <= 0.05 else f"off by {100 * gap:+.0f}%"))


if __name__ == "__main__":
    main()
