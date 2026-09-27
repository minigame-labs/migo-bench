#!/usr/bin/env python3
"""Aggregate one runtime's raw capture into a single provenance-stamped results row.

Usage:
  parse.py --header-only
  parse.py --label L --runtime R --game G --migo-version V --fps-source S \
           --meta META.txt --mem MEM.txt --fps FPS.txt [--cold-ms N]
"""
import argparse
import re
import statistics
import sys

COLUMNS = [
    "label", "runtime", "game",
    "device_model", "device_brand", "android_release", "android_sdk",
    "webview_version", "migo_version", "harness_version", "timestamp",
    "fps_source", "first_frame_ms", "game_ready_ms", "cpu_pct",
    "pss_peak_kb", "fps_median", "fps_1pct_low",
    # Appended, so every column before them keeps its position: CPU time per
    # cluster and the cycles it ran (scripts/cpu_clusters.py, MEASURING.md §14).
    "cpu_by_cluster", "gcycles_per_s", "cluster_check",
]


def read_kv(path):
    kv = {}
    with open(path) as f:
        for line in f:
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                kv[k.strip()] = v.strip()
    return kv


def pss_peak_kb(path):
    with open(path) as f:
        m = re.search(r"TOTAL PSS:\s*(\d+)", f.read())
    return m.group(1) if m else ""


def fps_stats(path):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if re.fullmatch(r"\d+(\.\d+)?", line):
                vals.append(float(line))
    if not vals:
        return "", ""
    vals_sorted = sorted(vals)
    median = round(statistics.median(vals_sorted))
    # 1% low = the 1st-percentile (worst) fps; for small N this is the minimum.
    idx = int(len(vals_sorted) * 0.01)
    low = round(vals_sorted[idx])
    return str(median), str(low)


def ensure(path):
    """Create the results file, or bring one written under an older column list
    up to this one.

    Columns are only ever appended, so an older file's header is a prefix of
    this one and its rows are padded with empty values for the rest -- the data
    keeps every position it had. Anything else is refused: rows of two
    schemas under one header would shift every column after the difference.
    """
    header = ",".join(COLUMNS)
    try:
        lines = open(path).read().splitlines()
    except FileNotFoundError:
        lines = []
    if not lines:
        with open(path, "w") as f:
            f.write(header + "\n")
        return
    old = lines[0].split(",")
    if old == COLUMNS:
        return
    if COLUMNS[: len(old)] != old:
        sys.exit(f"{path}: its columns are not a prefix of this harness's; not appending to it")
    pad = "," * (len(COLUMNS) - len(old))
    with open(path, "w") as f:
        f.write(header + "\n")
        for line in lines[1:]:
            f.write(line + pad + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--header-only", action="store_true")
    ap.add_argument("--ensure", metavar="CSV")
    ap.add_argument("--label")
    ap.add_argument("--runtime")
    ap.add_argument("--game")
    ap.add_argument("--migo-version", default="")
    ap.add_argument("--fps-source", default="")
    ap.add_argument("--meta")
    ap.add_argument("--mem")
    ap.add_argument("--fps")
    ap.add_argument("--cold-ms", default="")       # first-frame (Displayed)
    ap.add_argument("--game-ready-ms", default="")  # Fully drawn (game-ready)
    ap.add_argument("--cpu-pct", default="")
    a = ap.parse_args()

    if a.header_only:
        print(",".join(COLUMNS))
        return
    if a.ensure:
        ensure(a.ensure)
        return

    meta = read_kv(a.meta) if a.meta else {}
    fps_median, fps_low = fps_stats(a.fps) if a.fps else ("", "")
    row = {
        "label": a.label or "",
        "runtime": a.runtime or "",
        "game": a.game or "",
        "device_model": meta.get("device_model", ""),
        "device_brand": meta.get("device_brand", ""),
        "android_release": meta.get("android_release", ""),
        "android_sdk": meta.get("android_sdk", ""),
        "webview_version": meta.get("webview_version", ""),
        "migo_version": a.migo_version,
        "harness_version": meta.get("harness_version", ""),
        "timestamp": meta.get("timestamp", ""),
        "fps_source": a.fps_source,
        "first_frame_ms": a.cold_ms,
        "game_ready_ms": a.game_ready_ms,
        "cpu_pct": a.cpu_pct,
        "pss_peak_kb": pss_peak_kb(a.mem) if a.mem else "",
        "fps_median": fps_median,
        "fps_1pct_low": fps_low,
        "cpu_by_cluster": " ".join(
            f"{k[len('cpu_'):-len('_pct')]}:{v}" for k, v in meta.items()
            if k.startswith("cpu_cpu") and k.endswith("_pct")),
        "gcycles_per_s": meta.get("gcycles_per_s", ""),
        "cluster_check": meta.get("cluster_check", ""),
    }
    # Sanitize: no value may contain a comma (would break the CSV column count).
    print(",".join(str(row[c]).replace(",", ";") for c in COLUMNS))


if __name__ == "__main__":
    main()
