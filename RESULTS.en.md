# migo-bench Results

> Chinese is the default version — see [RESULTS.md](RESULTS.md). This is the English mirror.
> Raw data: `out/results.csv` (steady) and `out/stress_*.csv` (stress curve). Every row carries full provenance (Migo version, device, WebView version, timestamp, `fps_source`).

## 1. Bottom line

Same game, same device, same interaction, on the **Migo native runtime** vs the **Android System WebView**. Positioning: Migo = an open-source native WebView replacement. **The headline is consistency + auditability + memory/CPU efficiency; fps ties at normal load and is never oversold.**

- ✅ **Memory: Migo clearly lighter** (~147 MB vs WebView ~222 MB, **~34% less**). The catch: WebView renders in a **separate chromium process** that must be counted for fairness (otherwise WebView is undercounted by ~100 MB).
- ✅ **CPU: Migo about half of WebView** (~47% vs ~120%, same 100 sprites at 60 fps) — native GL is lighter than Chromium's compositor; also the energy proxy.
- ✅ **Throughput under heavy load: Migo clearly stronger** — the two diverge past 40k sprites; at 100k Migo 32 fps vs WebView 17 fps (**~1.9×**).
- ✅ **Startup resilience under heat: Migo faster** — game-ready is ~par on a cool device (506 vs 528 ms), but after sustained load / throttling Migo 506 ms vs WebView 1242 ms (**~2.4×**); WebView's Chromium cold start is amplified badly by throttling.
- = **fps (normal load): tie** (both ~60).
- ✅✅ **The heavier the game, the bigger the gap** — swapping in the real Phaser game endless-runner widens the memory gap from 33% to **61%** and CPU from ~2.6× to **~7×** (Migo's native cost is nearly fixed; WebView's Chromium tax grows with the app). See §3.6.
- ⚠️ **Honest counter-example (Canvas2D)** — the third game canvasmark takes the Canvas2D path: Migo **still wins CPU ~2× and ties fps**, but **memory is worse and churny** (~150–285 MB sawtooth vs WebView's stable ~221 MB). A real Migo GPU-resource leak this framework bisected (each Canvas2D fill draw leaks ~400 B of locked GL memory) — not hidden. See §3.7.

> Note: this is a **high-end** device (Kirin 990). Migo already leads on most metrics; the GTM wedge is **low-end** (less RAM, throttles easily), where memory/startup/heavy-load gaps should widen — low-end is the key next test (see the matrix).

## 2. Test matrix (device × game)

| Device tier \ game | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **High-end** · Huawei Mate30 Pro (Kirin 990 / 8 GB / A12) | ✅ done | ✅ done | ✅ done ⚠️ |
| **Mid** (~4 GB, to source) | 🔜 | 🔜 | 🔜 |
| **Low-end** ⭐ (~2–3 GB, to source, GTM wedge) | 🔜 | 🔜 | 🔜 |

> Currently 1 device × 3 games (two render paths: WebGL × 2 + Canvas2D × 1); the matrix fills in cell by cell as devices arrive.
> **Cross-game finding 1 (WebGL)**: a heavier, real Phaser game does not shrink Migo's lead — it **widens it sharply** (memory 33%→61%, CPU ~2.6×→~7×) — see §3.6.
> **Cross-game finding 2 (Canvas2D, honest counter-example ⚠️)**: on canvasmark Migo **still wins CPU ~2× and ties fps, but memory is worse** — root cause (bisected) = each Canvas2D fill draw leaks a locked GL resource, so memory churns to ~2× WebView. A real Migo GPU leak this framework surfaced — see §3.7.

## 3. Results: Mate30 Pro × bunnymark (100 sprites, 45 s steady)

### 3.1 Memory 🏆 Migo

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS peak | **~222 MB** | **~147 MB** | **Migo ~34% less** |

- **Fair accounting**: WebView = main process + chromium sandboxed renderer (`dumpsys meminfo <pkg>` counts only the main process, missing ~100 MB of renderer). Migo is **single-process**, fully counted.
- PSS has ±tens-of-MB jitter (GC / system state); the direction (Migo clearly lighter) is robust across runs.

### 3.2 Startup: par when cool, Migo more resilient under heat 🏆

**Game-ready (system `Fully drawn`, game's first real frame → `reportFullyDrawn()`, the fair metric):**

| device state | WebView | Migo | |
|---|---|---|---|
| **cool (fresh)** | 528 ms | 506 ms | ≈ par, Migo slightly faster |
| **hot / throttled (after hours of runs)** | **1242 ms** | **506 ms** | **Migo ~2.4× faster** |

- Cool: ~par (the V8 snapshot offsets native init). **Under heat, WebView's Chromium cold start (process spin-up + page load + JS init, CPU-heavy) is amplified badly by throttling, while Migo's snapshot restore is barely affected** — heat/throttling is exactly the **low-end + sustained-play** condition, a realistic Migo-favorable scenario.
- "first frame (`Displayed`)" fires on WebView's blank window (early, non-comparable across a WebView vs a SurfaceView), so **use game-ready**; Migo also has an extra Launcher→Game hop.

### 3.3 fps = tie at normal load; Migo scales far better under stress 🏆

**Stress curve (deterministic in-game ramp to 200k sprites, `--scenario stress`):**

| sprites | WebView fps | Migo fps | Migo × |
|---:|---:|---:|:---:|
| ≤20 000 | 60 | 59–60 | tie |
| **40 000** | 40 | **59** | Migo still 60, WebView dropping |
| **70 000** | 25 | **45** | ~1.8× |
| **100 000** | 17 | **32** | ~1.9× |
| 140 000 | 13 | 23 | ~1.8× |
| 180 000 | 10 | 17 | ~1.7× |
| 220 000 | (fell out) | 13 | Migo still running |

Both hold 60 fps to 20k (high-end ceiling is well beyond that). **Past 20k, native-GL Migo scales far better**: at 40k Migo is still 60 while WebView is 40; at 100k Migo 32 vs WebView 17 (**~1.9×**). WebView's knee is ~20–40k, Migo's ~40–70k — the real throughput gap that was hidden at ≤20k.

### 3.4 CPU 🏆 Migo

| metric | WebView | Migo | delta |
|---|---|---|---|
| CPU (multi-core, may exceed 100%) | **~120%** | **~47%** | **Migo ~half or less** |

- Method: `/proc/<pid>/stat` (utime+stime) delta; WebView includes the main + chromium renderer processes (same as memory).
- Half the CPU at the same fps → lower power (see Energy). Consistent across runs (~47% Migo vs ~108–123% WebView).

### 3.5 Energy (proxy)

Direct on-device energy is limited here: this EMUI device **disables the fuel gauge** (`current_now` unreadable) and the **per-uid batterystats energy model is unavailable**, and USB power masks battery drain. **CPU is used as the energy proxy** (at fixed fps, CPU is the dominant power driver) → Migo favorable. True energy awaits: (1) a non-Huawei device (open fuel gauge), (2) an unplugged run + battery-% delta, or (3) an external power meter.

## 3.6 Second game: endless-runner (Phaser) — the gap widens with a heavier game 🏆🏆

The second game is a full webpack build of the **Phaser 3** engine (a real mini-game, not a synthetic benchmark), same device / same method / 45 s steady:

| metric | WebView | Migo | delta |
|---|---|---|---|
| **PSS peak** | **~378 MB** | **~146 MB** | **Migo ~61% less** |
| **CPU (multi-core)** | **~125%** | **~18%** | **Migo ~1/7 of WebView** |
| game-ready (`Fully drawn`) | 654 ms | 631 ms | ≈ par |
| fps median / 1% low | 60 / 60 | 60 / 57 | tie |
| fps source | game-telemetry | game-telemetry | same source both sides (EMUI blocks SurfaceFlinger) |

**Cross-game comparison (this is the point):**

| metric | bunnymark (light, synthetic) | **endless-runner (heavy, real Phaser)** |
|---|---|---|
| memory (Migo vs WebView) | 147 vs 222 MB → 34% less | **146 vs 378 MB → 61% less** |
| CPU | 46% vs 122% → ~2.6× | **18% vs 125% → ~7×** |
| game-ready | 506 vs 528 → par | 631 vs 654 → par |
| fps | 60 / 60 | 60 / 60 |

**Takeaway**: with a heavier, real game Migo's lead **widens rather than shrinks**. Why: **Migo's native runtime cost is nearly game-independent** (146 MB ≈ bunnymark's 147 MB; CPU is even lower here since this game animates fewer objects than 100 bunnies) — a **fixed, low noise floor** — while **WebView's Chromium tax grows with the app** (memory 222→378 MB, CPU stays high). In other words, **the more real and heavy the game, the clearer Migo's advantage** — and real mini-games live in that region, not in toy benchmarks.

> Single-run sample (same basis as bunnymark's CPU/memory); the direction is large and robust, absolute values would tighten with multi-run averaging. endless-runner's fps telemetry uses an **engine-agnostic rAF counter** (identical injected code both sides, `[endless-runner] fps=N`); WebView game-ready fires from an injected `AndroidBench.ready()` first-frame callback, Migo from native onGameReady — this is the **telemetry contract** a new game satisfies to plug into the framework.

## 3.7 Third game: canvasmark (Canvas2D) — the honest counter-example ⚠️

The third game takes a **different rendering path**: pure Canvas 2D (not WebGL). canvasmark is the
2D analog of bunnymark — N rotating squares per frame via `save/translate/rotate/fillRect` (the
canvas2d hot path), tap to add, same 100 start. **Good news first: Migo implements Canvas2D
natively (Skia-backed) — `getContext('2d')` is a real 2D context, rendering at 60 fps** — so the
"WebView replacement" story covers 2D-canvas games, not only WebGL engines.

| metric | WebView | Migo | read |
|---|---|---|---|
| CPU (multi-core) | **173%** | **89%** | **Migo ~half** ✅ (Canvas2D is heavier than WebGL on both, but Migo still halves it) |
| fps median / 1% low | 60 / 60 | 60 / 58 | tie ✅ |
| game-ready | 380 ms | 450 ms | WebView ~18% faster |
| **PSS memory** | **~221 MB (stable)** | **~150–285 MB (churny)** | **⚠️ Migo worse** |

**Counter-example finding (the framework earning its keep)**: on canvasmark **Migo's memory is
higher and unstable** — a sawtooth between ~150–285 MB (grows ~3 MB/s, periodically purged) vs
WebView's stable ~221 MB. **The framework was used to bisect the root cause on-device:**

| probe | fills/frame | color changes/frame | GL memory over 40 s |
|---|---|---|---|
| background only | 1 | ~0 | **flat, 18 MB** |
| 100 fills, no transform | 101 | ~100 | 46→130 MB |
| 100 fills, fixed color | 101 | 2 | 37→122 MB |

- The growth is **entirely in GPU graphics memory** (`GL mtrack` in `dumpsys meminfo`); Java/Native
  heap are flat → **not the JS/GC heap** (my first hypothesis, JS `save/restore` allocation, was
  disproved by on-device measurement).
- It scales **purely with the number of fill draws per frame** (independent of color, transform,
  present) → **each Canvas2D fill draw leaks ~400 bytes of GL memory**.
- Those resources are **locked/referenced — Skia's cleanup can't purge them** (even forcing an
  aggressive 0 ms per-frame purge doesn't free them) → a **true GPU-resource leak in Migo's
  Canvas2D render path** (each draw leaves an unfreed GPU reference), not a cache or GC artifact.

**This is exactly what a benchmark is for** — not to cheerlead, but to honestly find **where Migo
needs work**. Verdict: **on the WebGL path Migo leads across the board (more so the heavier the
game); on the Canvas2D path Migo wins CPU and ties fps, but has a real per-draw GPU-resource leak
to fix**. When it's fixed, re-running canvasmark shows GL memory go flat — the regression harness
validating the fix (see README "Regression workflow"). fps holds 60 throughout.

> The leak is localized to "each fill draw leaks a locked GL resource," but the exact retaining
> reference needs deeper render-engine archaeology + GPU tooling — not fixed this round (no
> guess-fixes). fps telemetry is the game's own rAF counter `[canvasmark] sprites=N fps=M`.

## 4. Measurement method (system-level, app-agnostic, auditable)

- **Memory**: `dumpsys meminfo`; WebView sums main + `:sandboxed_process` (`webview_pss.py`).
- **Startup**: system `am` `Displayed` (first frame) + `reportFullyDrawn`/`Fully drawn` (game-ready); no app-log parsing. WebView gets game-ready via a JS bridge (`AndroidBench.ready()` on the game's first frame → `reportFullyDrawn()`).
- **fps**: prefer `dumpsys SurfaceFlinger --latency` (compositor present-timestamps, app-agnostic); **this EMUI device blocks it (all zeros)**, so fall back to the game's own fps telemetry (same source both sides, symmetric), recorded per row as `fps_source`. Non-Huawei devices use SurfaceFlinger.
- **CPU**: `/proc/<pid>/stat` delta (WebView incl. renderer).
- **Stress**: deterministic in-game sprite ramp (Pixi ticker, identical both sides; generated by `make-stress-game.sh`), fps plotted vs sprite count.
- **Stability guard**: force screen-on before capture (`svc power stayon`) — a slept screen stops the activity and yields zero frames/data.
- **Startup-time parsing**: ActivityManager writes `+868ms` below 1s but `+1s43ms` at/above 1s — the parser must handle s/m units (otherwise slow / low-end starts are silently dropped).
- **Thermal note**: after hours of continuous runs the Kirin 990 throttles (cold start up to 2–3× slower). Measuring both runtimes **back-to-back** in one pass keeps the *relative* comparison fair; absolute values want a cool-device re-run. Low-end devices throttle more readily — this is a realistic condition.

## 5. Reproduce

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# steady:
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 45 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 45 --cold-runs 3 --migo-aar local:.../migo-debug.aar
# stress curve (ramp to 200k):
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
```

```bash
# compare / regression gate (Migo vs WebView table, or new Migo vs baseline):
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview
python3 scripts/compare.py --results out/results.csv --baseline baselines/mate30.csv --game bunnymark
```

Pin the Migo version with `--migo-aar local:PATH | release-tag:TAG | sha:SHA` — every result is tied to an exact Migo version (auditability). Baseline snapshots live in `baselines/`; any future Migo optimization re-runs the capture and diffs good/bad against them (see README "Regression workflow").
