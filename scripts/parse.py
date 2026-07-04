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
    "fps_source", "cold_start_ms", "pss_peak_kb", "fps_median", "fps_1pct_low",
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--header-only", action="store_true")
    ap.add_argument("--label")
    ap.add_argument("--runtime")
    ap.add_argument("--game")
    ap.add_argument("--migo-version", default="")
    ap.add_argument("--fps-source", default="")
    ap.add_argument("--meta")
    ap.add_argument("--mem")
    ap.add_argument("--fps")
    ap.add_argument("--cold-ms", default="")
    a = ap.parse_args()

    if a.header_only:
        print(",".join(COLUMNS))
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
        "cold_start_ms": a.cold_ms,
        "pss_peak_kb": pss_peak_kb(a.mem) if a.mem else "",
        "fps_median": fps_median,
        "fps_1pct_low": fps_low,
    }
    # Sanitize: no value may contain a comma (would break the CSV column count).
    print(",".join(str(row[c]).replace(",", ";") for c in COLUMNS))


if __name__ == "__main__":
    main()
