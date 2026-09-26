#!/usr/bin/env python3
"""Generate the README headline chart (Migo vs WebView) as theme-aware SVGs.

Small-multiples: three panels (memory / CPU / game-ready startup), each a grouped
bar chart over the three benchmark games. Migo = blue (the subject), WebView = gray
(the neutral baseline it replaces); every bar is direct-labeled so identity never
rests on color alone. Emits assets/headline-light.svg and assets/headline-dark.svg;
the README references both via <picture> so GitHub shows the right one per theme.

The numbers come from scripts/results-figures.py -- the same session and the same
reduction as RESULTS.md's generated blocks -- so re-measuring and re-running this
is the whole update:  python3 scripts/make-headline-chart.py

They used to be typed in here, and twice drifted from the page the README links to:
once for long enough that the headline contradicted RESULTS.md ("faster 2 of 3",
memory "~42%"), and again until 2026-09-26, when the chart still showed an August
session two re-measurements old.
"""
import json
import os
import subprocess
import sys

GAMES = ["Bunnymark", "Endless", "Canvasmark"]  # Pixi / Phaser / Canvas2D
KEYS = {"Bunnymark": "bunnymark", "Endless": "endless-runner", "Canvasmark": "canvasmark"}


def load_panels():
    """metric -> (unit, subtitle, {game: (webview, migo)}), from the published session."""
    out = subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), "results-figures.py"), "--json"],
                         check=True, capture_output=True, text=True).stdout
    figures = json.loads(out)
    games = figures["games"]
    global SESSION
    SESSION = figures["session"]

    def pair(game, metric, scale=1.0):
        g = games[KEYS[game]]
        return (g[f"webview_{metric}"]["median"] / scale, g[f"migo_{metric}"]["median"] / scale)

    mem = {g: pair(g, "pss_peak_kb", 1024) for g in GAMES}
    cpu = {g: pair(g, "cpu_pct") for g in GAMES}
    ready = {g: pair(g, "game_ready_ms") for g in GAMES}
    # Ratios from the unrounded medians, as results-figures.py computes them;
    # only the bar labels are rounded.
    less = [1 - m / w for w, m in mem.values()]
    times = [w / m for w, m in cpu.values()]
    faster = sum(m < w for w, m in ready.values())
    shown = lambda data: {g: (round(w), round(m)) for g, (w, m) in data.items()}
    return [
        ("Memory", "MB PSS", f"Migo {min(less):.0%}-{max(less):.0%} less", shown(mem)),
        ("CPU", "% multi-core", f"Migo {min(times):.1f}-{max(times):.1f}x less", shown(cpu)),
        ("Startup", "ms to game-ready", f"Migo faster on {faster} of {len(GAMES)}", shown(ready)),
    ]


SESSION = None
PANELS = load_panels()

THEMES = {
    "light": dict(ink="#0b0b0b", sub="#52514e", muted="#898781", axis="#c3c2b7",
                  webview="#8f8d86", migo="#2a78d6", onbar="#ffffff"),
    "dark": dict(ink="#ffffff", sub="#c3c2b7", muted="#898781", axis="#383835",
                 webview="#8f8d86", migo="#3987e5", onbar="#ffffff"),
}

W, H = 960, 410
ML, MR, MT, MB = 24, 24, 118, 56         # MT leaves a clear band for header + legend
GAP = 28
PW = (W - ML - MR - 2 * GAP) / 3          # panel width
PLOT_TOP, PLOT_BOT = MT, H - MB           # vertical plot band
FONT = 'font-family="system-ui,-apple-system,Segoe UI,sans-serif"'


def esc(s): return s.replace("&", "&amp;").replace("<", "&lt;")


def svg(theme_name, t):
    o = []
    o.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
             f'viewBox="0 0 {W} {H}" {FONT}>')
    # Header + legend (once for the whole figure)
    o.append(f'<text x="{ML}" y="30" font-size="20" font-weight="700" '
             f'fill="{t["ink"]}">Migo vs Android System WebView</text>')
    o.append(f'<text x="{ML}" y="50" font-size="12.5" fill="{t["sub"]}">'
             f'Same game, same device (Mate30 Pro), same script - lower is better on all three.</text>')
    lx = W - MR - 232
    o.append(f'<rect x="{lx}" y="20" width="12" height="12" rx="3" fill="{t["webview"]}"/>')
    o.append(f'<text x="{lx+18}" y="30" font-size="12.5" fill="{t["sub"]}">WebView</text>')
    o.append(f'<rect x="{lx+96}" y="20" width="12" height="12" rx="3" fill="{t["migo"]}"/>')
    o.append(f'<text x="{lx+114}" y="30" font-size="12.5" font-weight="600" fill="{t["ink"]}">Migo</text>')

    for pi, (metric, unit, subtitle, data) in enumerate(PANELS):
        px = ML + pi * (PW + GAP)
        # panel title: metric name (left) + unit (right, muted) on one line — no
        # inline tspan (rsvg's x-advance for it is unreliable), then the takeaway.
        o.append(f'<text x="{px}" y="{MT-34}" font-size="15" font-weight="700" '
                 f'fill="{t["ink"]}">{esc(metric)}</text>')
        o.append(f'<text x="{px+PW:.0f}" y="{MT-34}" font-size="11.5" text-anchor="end" '
                 f'fill="{t["muted"]}">{esc(unit)}</text>')
        o.append(f'<text x="{px}" y="{MT-15}" font-size="12.5" font-weight="700" '
                 f'fill="{t["migo"]}">{esc(subtitle)}</text>')
        # baseline
        o.append(f'<line x1="{px}" y1="{PLOT_BOT}" x2="{px+PW}" y2="{PLOT_BOT}" '
                 f'stroke="{t["axis"]}" stroke-width="1"/>')
        vmax = max(max(v) for v in data.values()) * 1.18   # headroom for labels
        gw = PW / len(GAMES)
        bw = 26
        for gi, g in enumerate(GAMES):
            wv, mg = data[g]
            cx = px + gi * gw + gw / 2
            for j, (val, col, name) in enumerate(((wv, t["webview"], "WebView"), (mg, t["migo"], "Migo"))):
                bx = cx - bw - 2 + j * (bw + 4)
                bh = (PLOT_BOT - PLOT_TOP) * (val / vmax)
                by = PLOT_BOT - bh
                o.append(f'<rect x="{bx:.1f}" y="{by:.1f}" width="{bw}" height="{bh:.1f}" '
                         f'rx="4" fill="{col}"/>')
                # value label above the bar
                o.append(f'<text x="{bx+bw/2:.1f}" y="{by-6:.1f}" font-size="12" '
                         f'font-weight="{"700" if j else "400"}" text-anchor="middle" '
                         f'fill="{t["migo"] if j else t["sub"]}">{val}</text>')
            # game label under the group
            o.append(f'<text x="{cx:.1f}" y="{PLOT_BOT+20:.1f}" font-size="12" '
                     f'text-anchor="middle" fill="{t["sub"]}">{esc(g)}</text>')

    o.append(f'<text x="{ML}" y="{H-16}" font-size="11" fill="{t["muted"]}">'
             f'Median fps 60 on both sides; Endless game-ready is inside run-to-run noise. '
             f'Session {esc(SESSION)} - see RESULTS.</text>')
    o.append("</svg>")
    return "\n".join(o)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "assets")
    os.makedirs(out, exist_ok=True)
    for name, t in THEMES.items():
        p = os.path.join(out, f"headline-{name}.svg")
        with open(p, "w") as f:
            f.write(svg(name, t))
        print("wrote", p)


if __name__ == "__main__":
    main()
