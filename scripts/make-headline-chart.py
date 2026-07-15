#!/usr/bin/env python3
"""Generate the README headline chart (Migo vs WebView) as theme-aware SVGs.

Small-multiples: three panels (memory / CPU / game-ready startup), each a grouped
bar chart over the three benchmark games. Migo = blue (the subject), WebView = gray
(the neutral baseline it replaces); every bar is direct-labeled so identity never
rests on color alone. Emits assets/headline-light.svg and assets/headline-dark.svg;
the README references both via <picture> so GitHub shows the right one per theme.

Numbers are the Mate30 Pro release re-run in RESULTS.md (§3.1/§3.4/§3.2). Update
them here and re-run:  python3 scripts/make-headline-chart.py
"""
import os

GAMES = ["Bunnymark", "Endless", "Canvasmark"]  # Pixi / Phaser / Canvas2D
# metric -> (unit, subtitle, lower_is_better, {game: (webview, migo)})
PANELS = [
    ("Memory", "MB PSS", "Migo ~42% less", {
        "Bunnymark": (227, 132), "Endless": (382, 226), "Canvasmark": (213, 118)}),
    ("CPU", "% multi-core", "Migo ~2x less", {
        "Bunnymark": (118, 46), "Endless": (127, 44), "Canvasmark": (160, 83)}),
    ("Startup", "ms to game-ready", "Migo faster (2 of 3)", {
        "Bunnymark": (697, 495), "Endless": (671, 710), "Canvasmark": (517, 473)}),
]

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
             f'fps ties (~58 vs 60) and heavy-load stress is at parity as of #40 - see RESULTS.</text>')
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
