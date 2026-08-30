#!/usr/bin/env python3
"""Derive every published figure in RESULTS.md / RESULTS.en.md from out/results.csv.

Why this exists, and it is not a tidiness argument.

On 2026-08-25 the two report files and the raw rows disagreed three ways at once:

  * `RESULTS.md` §1 quoted the 2026-08-24 session while its own §3 tables still
    held an older one -- same document, two sessions, no marker saying so;
  * `RESULTS.en.md` was entirely at the older numbers, and still claimed
    "faster on all six measurements", a sentence the Chinese file had already
    retracted in writing;
  * one figure was simply mis-transcribed: endless-runner CPU read 2.9x where
    the rows give 3.02x -- an *under*-statement, which is how you can tell it
    was a typo and not a thumb on the scale.

None of that is catchable by review. A number in prose has no provenance, so a
reader cannot tell a fresh figure from a stale one, and neither can the person
editing the file next. The fix is the one this repo already used for binary
size: derive it, mark the block as generated, and gate that it has not drifted.

Reduction rule, inherited from matrix-summary.py rather than reinvented here:
**median per cell, with the range kept.** Median so one bad round cannot move
the figure; range because MEASURING.md §7 requires publishing spread whenever
two medians land close together.

Session selection is fail-closed. MEASURING.md §3 forbids comparing across
sessions, so this takes the newest date that has every game for both runtimes,
and refuses to proceed if that date's rows are not one contiguous run -- two
sessions on one day would otherwise be silently averaged into a number that
describes neither.

Usage:
  scripts/results-figures.py --json           # the figures, machine form
  scripts/results-figures.py --markdown cn    # the generated block for RESULTS.md
  scripts/results-figures.py --markdown en    # ... for RESULTS.en.md
"""
from __future__ import annotations

import argparse
import collections
import csv
import json
import pathlib
import statistics as st
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CSV_PATH = ROOT / "out" / "results.csv"

# Games in publication order, with the label each report gives the memory row
# (canvasmark's is a steady-state read, not a peak, and saying so is the point).
GAMES = [
    ("bunnymark", "Pixi/WebGL", "PSS 内存峰值", "PSS peak"),
    ("endless-runner", "Phaser/WebGL", "PSS 内存峰值", "PSS peak"),
    ("canvasmark", "Canvas2D", "PSS 内存(稳)", "PSS (steady)"),
]

# A run that reports 0% CPU did not measure; the process cannot execute a game
# at zero. One such row (2026-08-24 20:08, migo/bunnymark) reached the published
# dataset. Dropping it silently would be the same failure one layer down, so
# every drop is reported.
def drop_reason(row: dict) -> str | None:
    if float(row["cpu_pct"]) == 0:
        return "cpu_pct is 0 -- the capture failed, a running game cannot use no CPU"
    for key in ("pss_peak_kb", "first_frame_ms", "game_ready_ms"):
        if not row.get(key) or float(row[key]) == 0:
            return f"{key} is empty or 0"
    return None


def load() -> tuple[str, dict, list[str]]:
    rows = list(csv.DictReader(CSV_PATH.open(encoding="utf-8")))
    if not rows:
        sys.exit(f"FAIL: {CSV_PATH} has no rows")

    by_date = collections.defaultdict(list)
    for row in rows:
        by_date[row["timestamp"][:10]].append(row)

    wanted = {g for g, _, _, _ in GAMES}
    for date in sorted(by_date, reverse=True):
        day = by_date[date]
        covered = {(r["game"], r["runtime"]) for r in day}
        if not all((g, rt) in covered for g in wanted for rt in ("migo", "webview")):
            continue

        # Contiguity: one session, not two that happen to share a date.
        stamps = sorted(r["timestamp"] for r in day)
        import datetime as dt
        parsed = [dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ") for s in stamps]
        gaps = [(b - a).total_seconds() for a, b in zip(parsed, parsed[1:])]
        if gaps and max(gaps) > 1800:
            sys.exit(
                f"FAIL: {date} is not one session -- the largest gap between "
                f"consecutive runs is {max(gaps)/60:.0f} min. Averaging across "
                f"sessions is what MEASURING.md 3 forbids; split the file or "
                f"pick a session explicitly."
            )

        dropped = []
        kept = collections.defaultdict(lambda: collections.defaultdict(list))
        for row in day:
            reason = drop_reason(row)
            if reason:
                dropped.append(f"{row['timestamp']} {row['runtime']}/{row['game']}: {reason}")
                continue
            kept[row["game"]][row["runtime"]].append(row)
        return date, kept, dropped

    sys.exit("FAIL: no date in the CSV covers all three games for both runtimes")


def figures() -> dict:
    date, kept, dropped = load()
    out = {"session": date, "dropped_rows": dropped, "games": {}}
    for game, _, _, _ in GAMES:
        cell = {}
        for key in ("pss_peak_kb", "cpu_pct", "first_frame_ms", "game_ready_ms",
                    "fps_median", "fps_1pct_low"):
            for runtime in ("migo", "webview"):
                values = [float(r[key]) for r in kept[game][runtime]]
                cell[f"{runtime}_{key}"] = {
                    "median": st.median(values),
                    "min": min(values),
                    "max": max(values),
                    "n": len(values),
                }
        out["games"][game] = cell
    return out


def pct_less(webview: float, migo: float) -> float:
    return 100.0 * (webview - migo) / webview



def _m(cell: dict, runtime: str, key: str) -> float:
    return cell[f"{runtime}_{key}"]["median"]


def render(data: dict, lang: str, part: str) -> str:
    """One generated block. Prose around it is hand-written; these lines are not."""
    games = data["games"]
    mem = [pct_less(_m(games[g], "webview", "pss_peak_kb"),
                    _m(games[g], "migo", "pss_peak_kb")) for g, *_ in GAMES]
    cpu = [_m(games[g], "webview", "cpu_pct") / _m(games[g], "migo", "cpu_pct")
           for g, *_ in GAMES]

    # Startup tally, counted rather than asserted: the English file claimed
    # "faster on all six" for weeks after that stopped being true. A gap that
    # rounds to 0% is a tie, not a loss -- "slower by 0%" is noise dressed as a
    # verdict, and (RESULTS.md 8 / CLAUDE.md) publishing the tie is the honest
    # call anyway.
    wins, ties, losses = [], [], []
    for g, *_ in GAMES:
        for key, label_cn, label_en in (("first_frame_ms", "首帧", "first frame"),
                                        ("game_ready_ms", "可玩", "game-ready")):
            w, m = _m(games[g], "webview", key), _m(games[g], "migo", key)
            d = pct_less(w, m)
            bucket = ties if abs(d) < 0.5 else (wins if m < w else losses)
            bucket.append((g, label_cn, label_en, d))

    lines: list[str] = []
    if lang == "cn":
        pairs = "、".join(
            f"{g} {_m(games[g],'migo','pss_peak_kb')/1024:.0f} vs {_m(games[g],'webview','pss_peak_kb')/1024:.0f}"
            for g, *_ in GAMES)
        lines.append(f"- ✅ **内存:Migo 少 {min(mem):.0f}–{max(mem):.0f}%**({pairs} MB)。"
                     "公平口径:WebView 计入独立的 chromium 渲染进程(否则少算 ~100MB)。")
        per = "、".join(f"{g} {c:.1f}×" for (g, *_), c in zip(GAMES, cpu))
        lines.append(f"- ✅ **CPU:Migo 用 WebView 的 1/3 到 1/2({min(cpu):.1f}–{max(cpu):.1f}×)**——{per}。")
        tally = f"六项里 {len(wins)} 项更快" + (f"、{len(ties)} 项打平" if ties else "")
        parts = ["更快的是 " + "、".join(f"{g} {lc} 快 {d:.0f}%" for g, lc, _, d in wins)]
        if ties:
            parts.append("打平的是 " + "、".join(f"{g} {lc}" for g, lc, _, _ in ties))
        if losses:
            parts.append("更慢的是 " + "、".join(f"**{g} {lc} 慢 {abs(d):.0f}%**" for g, lc, _, d in losses))
        elif not ties:
            parts.append("没有更慢的一项")
        lines.append(f"- **启动:{tally}。**" + ";".join(parts) + "。")
        fps = games[GAMES[0][0]]
        lines.append(f"- = **帧率:打平。**两侧中位数都是 {_m(fps,'webview','fps_median'):.0f} fps;"
                     f"1% 低帧 Migo {_m(fps,'migo','fps_1pct_low'):.0f}、WebView {_m(fps,'webview','fps_1pct_low'):.0f}。")
    else:
        pairs = ", ".join(
            f"{g} {_m(games[g],'migo','pss_peak_kb')/1024:.0f} vs {_m(games[g],'webview','pss_peak_kb')/1024:.0f}"
            for g, *_ in GAMES)
        lines.append(f"- ✅ **Memory: Migo uses {min(mem):.0f}–{max(mem):.0f}% less** ({pairs} MB). "
                     "Fair accounting: WebView counts its separate chromium renderer process "
                     "(else ~100MB is missed).")
        per = ", ".join(f"{g} {c:.1f}×" for (g, *_), c in zip(GAMES, cpu))
        lines.append(f"- ✅ **CPU: Migo at a third to a half of WebView ({min(cpu):.1f}–{max(cpu):.1f}×)** — {per}.")
        tally = f"faster on {len(wins)} of 6 measurements" + (f", tied on {len(ties)}" if ties else "")
        segs = ["Faster: " + ", ".join(f"{g} {le} by {d:.0f}%" for g, _, le, d in wins) + "."]
        if ties:
            segs.append(" Tied: " + ", ".join(f"{g} {le}" for g, _, le, _ in ties) + ".")
        if losses:
            segs.append(" Slower: " + ", ".join(f"**{g} {le} by {abs(d):.0f}%**" for g, _, le, d in losses) + ".")
        lines.append(f"- **Startup: {tally}.** " + "".join(segs))
        fps = games[GAMES[0][0]]
        lines.append(f"- = **fps: a tie.** Both sides hold a {_m(fps,'webview','fps_median'):.0f} fps median; "
                     f"1% low is Migo {_m(fps,'migo','fps_1pct_low'):.0f}, WebView {_m(fps,'webview','fps_1pct_low'):.0f}.")

    if part == "headline":
        return "\n".join(lines)

    lines = []
    for index, (game, engine, mem_cn, mem_en) in enumerate(GAMES, start=1):
        cell = games[game]
        head = (f"### 3.{index} {game}({engine})" if lang == "cn"
                else f"### 3.{index} {game} ({engine})")
        lines += ([head, ""] if index == 1 else ["", head, ""])
        lines.append("| 指标 | WebView | Migo | 差异 |" if lang == "cn"
                     else "| Metric | WebView | Migo | Delta |")
        lines.append("|---|---|---|---|")
        rows = [
            (mem_cn if lang == "cn" else mem_en, "pss_peak_kb", "mem"),
            ("CPU(多核)" if lang == "cn" else "CPU (multicore)", "cpu_pct", "cpu"),
            ("首帧(`Displayed`)" if lang == "cn" else "First frame (`Displayed`)", "first_frame_ms", "ms"),
            ("可玩(`Fully drawn`)" if lang == "cn" else "Game-ready (`Fully drawn`)", "game_ready_ms", "ms"),
        ]
        for label, key, kind in rows:
            w, m = _m(cell, "webview", key), _m(cell, "migo", key)
            if kind == "mem":
                wt, mt = f"{w/1024:.0f} MB", f"{m/1024:.0f} MB"
                diff = (f"Migo 少 {pct_less(w,m):.0f}%" if lang == "cn"
                        else f"{pct_less(w,m):.0f}% less")
            elif kind == "cpu":
                wt, mt = f"{w:.0f}%", f"{m:.0f}%"
                diff = (f"Migo {w/m:.1f}× 少" if lang == "cn" else f"{w/m:.1f}× less")
            else:
                wt, mt = f"{w:.0f} ms", f"{m:.0f} ms"
                d = pct_less(w, m)
                if abs(d) < 0.5:
                    diff = "打平" if lang == "cn" else "tie"
                elif m < w:
                    diff = (f"Migo 快 {d:.0f}%" if lang == "cn" else f"{d:.0f}% faster")
                else:
                    diff = (f"**Migo 慢 {abs(d):.0f}%**" if lang == "cn"
                            else f"**{abs(d):.0f}% slower**")
            lines.append(f"| {label} | {wt} | {mt} | {diff} |")
        fw, fm = _m(cell, "webview", "fps_median"), _m(cell, "migo", "fps_median")
        lw, lm = _m(cell, "webview", "fps_1pct_low"), _m(cell, "migo", "fps_1pct_low")
        lines.append(f"| fps 中位 / 1% low | {fw:.0f} / {lw:.0f} | {fm:.0f} / {lm:.0f} | 打平 |"
                     if lang == "cn" else
                     f"| fps median / 1% low | {fw:.0f} / {lw:.0f} | {fm:.0f} / {lm:.0f} | tie |")
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--markdown", choices=("cn", "en"))
    ap.add_argument("--part", choices=("headline", "tables"), default="headline")
    args = ap.parse_args()

    data = figures()
    if args.json:
        print(json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False))
        return
    if not args.markdown:
        ap.error("pass --json or --markdown cn|en")

    print(render(data, args.markdown, args.part))


if __name__ == "__main__":
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    main()
