# canvasmark (Canvas 2D)

The third bench game — the **Canvas 2D-path** analog of bunnymark (which is WebGL/Pixi). Pure
vanilla Canvas2D: no engine, no CDN, no image assets. Draws N bouncing, rotating squares per
frame via `ctx.save/translate/rotate/fillStyle/fillRect` — the canvas2d hot path — plus a
full-screen `fillRect` background. Tap to add 100 sprites. Starts at 100 (same as bunnymark →
a fair same-count comparison of the 2D path vs the WebGL path).

## Why this matters

It exercises a **different rendering path** from the other two games. bunnymark (Pixi v8) and
endless-runner (Phaser) both go through WebGL; canvasmark goes through the 2D context.
**Migo implements Canvas 2D natively (Skia-backed)** — `getContext('2d')` routes to a real
`CanvasRenderingContext2D` with the full surface (rects, paths, text, transforms, gradients,
`drawImage`, shadows). Verified rendering at 60 fps on the Mate30 Pro. So the "WebView
replacement" story covers 2D-canvas games too, not only WebGL engines.

## Payloads (`dist/`)

- `game.bundle.js` — the game (shared source; runs as-is in the browser).
- `index.html` + `game.bundle.js` — browser build for `webview-shell` (native Canvas 2D).
- `game.js` — Migo build: the `migo-web-adapter` IIFE prelude (browser globals → `migo.*`) prepended
  to `game.bundle.js`. Regenerate from a checkout of
  [minigame-labs/migo-web-adapter](https://github.com/minigame-labs/migo-web-adapter) with:
  `npm run build && cat dist/migo-web-adapter.bundle.js <bench>/games/canvasmark/dist/game.bundle.js > game.js`
  (plus the header line and a `;` separator between the two IIFEs — see the existing `game.js` for the
  exact format).

## Telemetry contract

Baked into `game.bundle.js` (so both runtimes share identical code): logs
`[canvasmark] sprites=N fps=M` via `console.error` (reaches Android logcat; the harness's
fallback fps source when the OEM blocks SurfaceFlinger), and calls `AndroidBench.ready()` once
on the first frame so the WebView shell's `reportFullyDrawn()` fires (Migo signals ready
natively; `AndroidBench` is undefined there → guarded no-op).

## Run

```bash
bash scripts/run.sh --runtime webview --game canvasmark --device <SERIAL> --duration 45 --cold-runs 3
bash scripts/run.sh --runtime migo    --game canvasmark --device <SERIAL> --duration 45 --cold-runs 3 --migo-aar local:.../migo-debug.aar
```

`--game canvasmark` → `GAME_ASSET=game-canvasmark`, threaded into every launch by `scripts/lib.sh`.
