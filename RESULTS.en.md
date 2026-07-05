# migo-bench Results

> Chinese is the default version — see [RESULTS.md](RESULTS.md). This is the English mirror.
> Raw data: `out/results.csv` (steady) and `out/stress_*.csv` (stress curve). Every row carries full provenance (Migo version, device, WebView version, timestamp, `fps_source`).

## 1. Bottom line

Same game, same device, same interaction, on the **Migo native runtime** vs the **Android System WebView**. Positioning: Migo = an open-source native WebView replacement. **The headline is consistency + auditability + memory/CPU efficiency; fps ties at normal load and is never oversold.**

- ✅ **Memory: Migo clearly lighter** (~150 MB vs WebView ~222 MB, **~33% less**). The catch: WebView renders in a **separate chromium process** that must be counted for fairness (otherwise WebView is undercounted by ~100 MB).
- ✅ **CPU: Migo about half of WebView** (~47% vs ~120%, same 100 sprites at 60 fps) — native GL is lighter than Chromium's compositor; also the energy proxy.
- ✅ **Throughput under heavy load: Migo clearly stronger** — the two diverge past 40k sprites; at 100k Migo 32 fps vs WebView 17 fps (**~1.9×**).
- ✅ **Startup resilience under heat: Migo faster** — game-ready is ~par on a cool device (525 vs 537 ms), but after sustained load / throttling Migo 506 ms vs WebView 1242 ms (**~2.4×**); WebView's Chromium cold start is amplified badly by throttling.
- = **fps (normal load): tie** (both ~60).
- ✅✅ **The heavier the game, the bigger the gap** — swapping in the real Phaser game endless-runner widens the memory gap from 33% to **61%** and CPU from ~2.6× to **~7×** (Migo's native cost is nearly fixed; WebView's Chromium tax grows with the app). See §3.6.

> Note: this is a **high-end** device (Kirin 990). Migo already leads on most metrics; the GTM wedge is **low-end** (less RAM, throttles easily), where memory/startup/heavy-load gaps should widen — low-end is the key next test (see the matrix).

## 2. Test matrix (device × game)

| Device tier \ game | bunnymark (Pixi v8) | endless-runner (Phaser) | Canvas2D (TBD) |
|---|---|---|---|
| **High-end** · Huawei Mate30 Pro (Kirin 990 / 8 GB / A12) | ✅ done | ✅ done | 🔜 planned |
| **Mid** (~4 GB, to source) | 🔜 | 🔜 | 🔜 |
| **Low-end** ⭐ (~2–3 GB, to source, GTM wedge) | 🔜 | 🔜 | 🔜 |

> Currently 1 device × 2 games is running; the matrix fills in cell by cell as devices arrive. Each cell yields the metric set below.
> **Key cross-game finding**: swapping in a heavier, real Phaser game does not shrink Migo's lead — it **widens it sharply** (memory gap 33%→61%, CPU ~2.6×→~7×) — see §3.6.

## 3. Results: Mate30 Pro × bunnymark (100 sprites, 45 s steady)

### 3.1 Memory 🏆 Migo

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS peak | **~222 MB** | **~150 MB** | **Migo ~33% less** |

- **Fair accounting**: WebView = main process + chromium sandboxed renderer (`dumpsys meminfo <pkg>` counts only the main process, missing ~100 MB of renderer). Migo is **single-process**, fully counted.
- PSS has ±tens-of-MB jitter (GC / system state); the direction (Migo clearly lighter) is robust across runs.

### 3.2 Startup: par when cool, Migo more resilient under heat 🏆

**Game-ready (system `Fully drawn`, game's first real frame → `reportFullyDrawn()`, the fair metric):**

| device state | WebView | Migo | |
|---|---|---|---|
| **cool (fresh)** | 537 ms | 525 ms | ≈ par, Migo slightly faster |
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
| memory (Migo vs WebView) | 150 vs 222 MB → 33% less | **146 vs 378 MB → 61% less** |
| CPU | 47% vs 120% → ~2.6× | **18% vs 125% → ~7×** |
| game-ready | 525 vs 537 → par | 631 vs 654 → par |
| fps | 60 / 60 | 60 / 60 |

**Takeaway**: with a heavier, real game Migo's lead **widens rather than shrinks**. Why: **Migo's native runtime cost is nearly game-independent** (146 MB ≈ bunnymark's 150 MB; CPU is even lower here since this game animates fewer objects than 100 bunnies) — a **fixed, low noise floor** — while **WebView's Chromium tax grows with the app** (memory 222→378 MB, CPU stays high). In other words, **the more real and heavy the game, the clearer Migo's advantage** — and real mini-games live in that region, not in toy benchmarks.

> Single-run sample (same basis as bunnymark's CPU/memory); the direction is large and robust, absolute values would tighten with multi-run averaging. endless-runner's fps telemetry uses an **engine-agnostic rAF counter** (identical injected code both sides, `[endless-runner] fps=N`); WebView game-ready fires from an injected `AndroidBench.ready()` first-frame callback, Migo from native onGameReady — this is the **telemetry contract** a new game satisfies to plug into the framework.

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

Pin the Migo version with `--migo-aar local:PATH | release-tag:TAG | sha:SHA` — every result is tied to an exact Migo version (auditability).
