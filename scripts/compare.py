#!/usr/bin/env python3
"""Compare two benchmark result rows and emit a markdown delta table.

This is the regression-harness core: it turns a results.csv into a decision. Two uses:

  # Migo vs WebView (one results.csv, both runtimes for a game) -> the showcase table.
  compare.py --results out/results.csv --game bunnymark --vs-webview

  # Regression gate: a NEW Migo run vs a pinned Migo baseline (same game).
  # Exits non-zero if any metric regressed past --threshold -> use in CI / before merge.
  compare.py --results out/results.csv --baseline baselines/bunnymark-mate30.csv \
             --game bunnymark

Metrics carry a direction (lower-better: memory/CPU/startup; higher-better: fps). A change
within +/- threshold percent is treated as noise (the single-run jitter documented in RESULTS).
"""
import argparse
import csv
import sys

# name -> (direction, human label, unit, scale-from-raw)
#   direction "low"  = smaller is better (memory, CPU, startup latency)
#   direction "high" = larger is better  (fps)
METRICS = [
    ("pss_peak_kb",    "low",  "PSS memory",  "MB", lambda v: round(int(v) / 1024)),
    ("cpu_pct",        "low",  "CPU",         "%",  int),
    ("first_frame_ms", "low",  "first-frame", "ms", int),
    ("game_ready_ms",  "low",  "game-ready",  "ms", int),
    ("fps_median",     "high", "fps median",  "",   int),
    ("fps_1pct_low",   "high", "fps 1% low",  "",   int),
]


def load_rows(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def pick(rows, game, runtime):
    """The last row matching game (+runtime); last wins so re-runs supersede."""
    hit = [r for r in rows if r.get("game") == game
           and (runtime is None or r.get("runtime") == runtime)]
    return hit[-1] if hit else None


def improvement_pct(base, cand, direction):
    """Signed % by which cand is BETTER than base (positive = cand better)."""
    if base == 0:
        return 0.0
    return (base - cand) / base * 100 if direction == "low" else (cand - base) / base * 100


def compare_rows(base, cand, threshold):
    """Per-metric comparison. Returns list of dicts; verdict in {better,worse,flat}.
    Metrics missing/empty on either side are skipped (not invented)."""
    out = []
    for name, direction, label, unit, scale in METRICS:
        b_raw, c_raw = base.get(name, ""), cand.get(name, "")
        if b_raw in ("", None) or c_raw in ("", None):
            continue
        try:
            b, c = scale(b_raw), scale(c_raw)
        except (ValueError, TypeError):
            continue
        imp = improvement_pct(b, c, direction)
        if abs(imp) <= threshold:
            verdict = "flat"
        elif imp > 0:
            verdict = "better"
        else:
            verdict = "worse"
        out.append({"name": name, "label": label, "unit": unit, "direction": direction,
                    "base": b, "cand": c, "improvement_pct": imp, "verdict": verdict})
    return out


_EMOJI = {"better": "✅", "worse": "⚠️", "flat": "≈"}


def render_md(cmp, base_name, cand_name, title):
    unit = lambda m: f" {m['unit']}" if m["unit"] else ""
    lines = [f"### {title}", "",
             f"| metric | {base_name} | {cand_name} | Δ (cand vs base) | |",
             "|---|---|---|---|---|"]
    for m in cmp:
        sign = "+" if m["improvement_pct"] >= 0 else ""
        lines.append(
            f"| {m['label']} | {m['base']}{unit(m)} | {m['cand']}{unit(m)} | "
            f"{sign}{m['improvement_pct']:.0f}% | {_EMOJI[m['verdict']]} |")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", required=True, help="candidate results.csv")
    ap.add_argument("--game", required=True)
    ap.add_argument("--vs-webview", action="store_true",
                    help="compare migo vs webview within --results (showcase table, no gate)")
    ap.add_argument("--baseline", help="baseline results.csv (regression gate vs its migo row)")
    ap.add_argument("--runtime", default="migo", help="runtime to gate in --baseline mode")
    ap.add_argument("--threshold", type=float, default=5.0, help="noise dead-band, percent")
    a = ap.parse_args()

    cand_rows = load_rows(a.results)

    if a.vs_webview:
        base = pick(cand_rows, a.game, "webview")
        cand = pick(cand_rows, a.game, "migo")
        if not base or not cand:
            print(f"ERROR: need both webview and migo rows for game={a.game}", file=sys.stderr)
            return 2
        cmp = compare_rows(base, cand, a.threshold)
        print(render_md(cmp, "WebView", "Migo",
                        f"{a.game}: Migo vs WebView (Δ = how much better Migo is)"))
        if any(m["name"] == "first_frame_ms" for m in cmp):
            print("\n> Note: first-frame is the system `Displayed` event — WebView's blank window "
                  "draws earlier and Migo adds a Launcher→Game hop, so it is NOT comparable across "
                  "runtimes. Use game-ready (`Fully drawn`) for startup.")
        return 0

    if a.baseline:
        base = pick(load_rows(a.baseline), a.game, a.runtime)
        cand = pick(cand_rows, a.game, a.runtime)
        if not base or not cand:
            print(f"ERROR: need {a.runtime} rows for game={a.game} in both files", file=sys.stderr)
            return 2
        cmp = compare_rows(base, cand, a.threshold)
        print(render_md(cmp, "baseline", "candidate",
                        f"{a.game} {a.runtime}: candidate vs baseline (regression gate)"))
        regressions = [m for m in cmp if m["verdict"] == "worse"]
        if regressions:
            names = ", ".join(f"{m['label']} {m['improvement_pct']:.0f}%" for m in regressions)
            print(f"\n⚠️ REGRESSION: {names} (> {a.threshold:.0f}% worse than baseline)",
                  file=sys.stderr)
            return 1
        print(f"\n✅ no regression past {a.threshold:.0f}% vs baseline", file=sys.stderr)
        return 0

    print("ERROR: pass --vs-webview or --baseline", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
