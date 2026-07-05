# endless-runner (Phaser 3)

The second bench game — a **real** mini-game (full Phaser 3 webpack build), not a
synthetic loop. It exists to show whether Migo's lead holds on a heavier, realistic
engine. It does (the gap *widens*): see [RESULTS.md](../../RESULTS.md) §3.6.

## Payloads (`dist/`)

- `game.js` — Migo build: migo-adapter prelude + the Phaser engine bundle, self-contained
  (loaded by `migo-shell` as the game entry point).
- `index.html` + `main.<hash>.js` — browser build for `webview-shell` (`index.html` loads
  the Phaser bundle). `main.<hash>.js.LICENSE.txt` is the webpack license banner (Phaser 3
  is MIT; PixiJS/other deps MIT).

## Telemetry contract (what a new game must satisfy)

Both payloads carry an identical injected snippet (marker `/*bench-fps-telemetry*/`):

- an **engine-agnostic rAF fps counter** — counts `requestAnimationFrame` callbacks per
  second (= achieved frame rate) and logs `[endless-runner] fps=N` via `console.error`
  (the channel that reaches Android logcat). Identical code both runtimes ⇒ symmetric/fair,
  and it's what the harness falls back to when the OEM blocks `dumpsys SurfaceFlinger`.
- a **first-frame ready hook** — calls `AndroidBench.ready()` once on the first frame so
  the WebView shell's `reportFullyDrawn()` fires (game-ready startup metric). On Migo
  `AndroidBench` is undefined → try/catch no-op; Migo signals ready via native onGameReady.

The injection is idempotent (keyed on the marker) so re-instrumenting a rebuilt bundle is safe.

## Run

```bash
bash scripts/run.sh --runtime webview --game endless-runner --device <SERIAL> --duration 45 --cold-runs 3
bash scripts/run.sh --runtime migo    --game endless-runner --device <SERIAL> --duration 45 --cold-runs 3 --migo-aar local:.../migo-debug.aar
```

`--game endless-runner` resolves to `GAME_ASSET=game-endless-runner`, threaded into every
launch (cold-start, game-ready, steady) by `scripts/lib.sh`. The stress scenario is
bunnymark-only (its ramp is Pixi-ticker specific).
