#!/usr/bin/env python3
"""Reduce out/matrix.csv to the per-cell figures a report or a site quotes.

The reduction is part of the claim. RESULTS.md §5.1 records a published
temperature figure that changed sign depending on whether "temperature" meant
the peak or the mean of a series -- so how a set of runs becomes one number is
not a detail to leave to whoever is writing the page that day.

This fixes it once: **median per cell, with the range kept**. Median because a
single bad round should not move the figure, and the range because MEASURING.md
§7 says to publish it whenever two medians land within ~10% of each other -- a
median without its spread is how "6% faster" gets quoted from three runs that
overlap.

Output is JSON, so a site or a report can consume it instead of transcribing
numbers by hand. Transcription is how a page ends up quoting a build nobody can
download.

Usage:
  scripts/matrix-summary.py [--matrix out/matrix.csv] [--out FILE]
  scripts/matrix-summary.py --format table    # human-readable
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timedelta
import json
import pathlib
import statistics
import sys

# The metrics a published comparison quotes, and which direction is better.
# `divisor` turns a raw column into the unit the reader sees.
METRICS = [
    ("pss_peak_kb", "pss_mb", 1024.0, 1),
    ("cpu_pct", "cpu_pct", 1.0, 0),
    ("first_frame_ms", "first_frame_ms", 1.0, 0),
    ("game_ready_ms", "game_ready_ms", 1.0, 0),
    ("fps_median", "fps_median", 1.0, 1),
    ("fps_1pct_low", "fps_1pct_low", 1.0, 1),
]


# One run, not every run the file has accumulated.
#
# `bench-matrix.sh` appends to out/matrix.csv and only writes a header when the
# file is absent, so the ledger holds every session ever taken on this machine.
# Summarising all of it blends measurements days apart -- exactly what
# MEASURING.md section 3 forbids, because the level drifts ~120 ms between
# sessions, which is larger than most effects being published. Before
# 2026-09-02 this function did not exist and the published table was whatever
# happened to be in the file.
#
# A session is a contiguous block in time: inside one run the cells are minutes
# apart, and runs are hours or days apart. So walk back from the newest row and
# stop at the first gap larger than SESSION_GAP. The boundary is printed, so a
# reader can check the split rather than trust it.
SESSION_GAP = timedelta(minutes=45)


def _parsed_time(row: dict[str, str]) -> datetime | None:
    raw = (row.get("timestamp") or "").strip()
    try:
        return datetime.strptime(raw, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None


def latest_session(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    stamped = [(t, r) for r in rows if (t := _parsed_time(r)) is not None]
    if not stamped:
        # No usable timestamps: summarising the whole file is still wrong, but
        # refusing outright would break a ledger written by an older harness.
        print("matrix-summary: no parseable timestamps; using every row",
              file=sys.stderr)
        return rows
    stamped.sort(key=lambda pair: pair[0])
    cut = 0
    for i in range(len(stamped) - 1, 0, -1):
        if stamped[i][0] - stamped[i - 1][0] > SESSION_GAP:
            cut = i
            break
    session = [r for _, r in stamped[cut:]]
    if cut:
        print(f"matrix-summary: using the {len(session)} row(s) from "
              f"{stamped[cut][0]:%Y-%m-%dT%H:%M:%SZ} onward; "
              f"{cut} older row(s) belong to earlier sessions", file=sys.stderr)
    return session


def main() -> int:
    here = pathlib.Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", default=str(here.parent / "out" / "matrix.csv"))
    parser.add_argument("--out")
    parser.add_argument("--format", choices=["json", "table"], default="json")
    args = parser.parse_args()

    path = pathlib.Path(args.matrix)
    if not path.is_file():
        print(f"no matrix at {path}; run scripts/bench-matrix.sh first", file=sys.stderr)
        return 2

    rows = list(csv.DictReader(path.open(encoding="utf-8")))
    if not rows:
        print(f"{path} has no rows", file=sys.stderr)
        return 2

    rows = latest_session(rows)

    # A row whose gate timed out was not taken under the same device state as
    # the others. Counting it would silently mix two conditions, so it is
    # excluded and said out loud rather than averaged in.
    ungated = [r for r in rows if r.get("gate", "").startswith("TIMEOUT")]
    rows = [r for r in rows if not r.get("gate", "").startswith("TIMEOUT")]
    if not rows:
        print("every row was ungated; nothing comparable to report", file=sys.stderr)
        return 2

    cells: dict[tuple[str, str], list[dict[str, str]]] = {}
    for row in rows:
        cells.setdefault((row["game"], row["runtime"]), []).append(row)

    # Provenance columns are not all present on every row: a webview row carries
    # no migo version and a migo row carries no webview version. Taking them all
    # from one row reported the Migo build as "n/a" on a table that was measuring
    # it.
    def first_nonempty(column: str) -> str:
        for row in rows:
            value = row.get(column, "")
            if value and value != "n/a":
                return value
        return ""

    provenance = rows[0]
    summary: dict[str, object] = {
        "source": path.name,
        "rows_used": len(rows),
        "rows_excluded_ungated": len(ungated),
        "device": provenance.get("device_model", ""),
        "android_sdk": provenance.get("android_sdk", ""),
        "webview_version": first_nonempty("webview_version"),
        "migo_version": first_nonempty("migo_version"),
        "harness_version": provenance.get("harness_version", ""),
        "measured": provenance.get("timestamp", ""),
        "games": {},
    }

    for (game, runtime), group in sorted(cells.items()):
        entry = summary["games"].setdefault(game, {})  # type: ignore[index]
        cell: dict[str, object] = {"runs": len(group)}
        for column, name, divisor, digits in METRICS:
            values = [
                float(r[column]) / divisor
                for r in group
                if r.get(column) not in (None, "", "n/a")
            ]
            if not values:
                continue
            cell[name] = {
                "median": round(statistics.median(values), digits),
                "min": round(min(values), digits),
                "max": round(max(values), digits),
            }
        entry[runtime] = cell

    if args.format == "table":
        print(f"device {summary['device']} · migo {summary['migo_version']} · "
              f"{summary['rows_used']} rows"
              + (f" ({summary['rows_excluded_ungated']} ungated excluded)"
                 if summary["rows_excluded_ungated"] else ""))
        for game, arms in summary["games"].items():  # type: ignore[union-attr]
            print(f"\n— {game}")
            names = [m[1] for m in METRICS]
            for name in names:
                parts = []
                for runtime in ("webview", "migo"):
                    stat = arms.get(runtime, {}).get(name)
                    parts.append(
                        f"{runtime} {stat['median']} [{stat['min']}–{stat['max']}]"
                        if stat else f"{runtime} —"
                    )
                print(f"   {name:16} " + "   ".join(parts))
        return 0

    text = json.dumps(summary, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    if args.out:
        pathlib.Path(args.out).write_text(text, encoding="utf-8")
        print(f"summary -> {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
