# migo-bench Results

> Chinese is the default; see [RESULTS.md](RESULTS.md). English mirror here.
> Raw data: `out/results.csv` (steady), `out/stress_*.csv` (stress curve). Every row carries full provenance.
> **This round (2026-07 re-run)**: Migo is built **release** (opt-z + LTO, the shipping config), superseding the earlier debug numbers. **And two rendering bugs were fixed before re-measuring** (see §0) — the prior version's canvasmark (Migo rendered only 1/9 of the screen) and endless-runner (blank landscape WebView) comparisons were invalid and are superseded by this page.

## 0. Two rendering bugs fixed this round (up front)

A fair comparison requires **both runtimes to render the whole game correctly**. On-device checking this round found and fixed:

1. **Migo canvasmark rendered only the top-left ~1/9 of the screen** (Canvas2D path). Root cause: on a surfaceChanged (status-bar area change) the engine forced the Canvas2D backing to the physical size, but a DPR-naive game reads the canvas size once at init and draws in logical coordinates forever → its drawing lands in a corner of an oversized backing. WebGL games re-read the canvas size every frame so they were unaffected; the earlier wx-way fix only covered WebGL. **Fixed** (migo `fix/canvas2d-onscreen-backing-corner`: preserve the backing's logical-vs-physical choice proportionally across a surface resize) → canvasmark now fills the screen, matching WebView.
2. **WebView endless-runner rendered blank (only sky) in landscape**. Root cause: the bench forced the WebView to landscape, and the rotation happened after Phaser had sized its canvas, stranding the game world off-screen. **Fixed**: lock the WebView to portrait (a browser runs the game in the device's natural orientation and Phaser fit-scales a landscape game into it). The Migo mini-game runtime honors game.json (landscape) natively — different orientation, but both render the whole game at the same pixel budget.

After the fixes, all three games render full-screen/correctly on both runtimes (verified on device). The numbers below are post-fix.

## 1. TL;DR

Same game, same device, same interaction. **Migo native runtime (release)** vs **Android System WebView**. Positioning: Migo = the open-source native WebView replacement.

- ✅ **Memory: Migo clearly lower, consistent ~40–44% across all three** (bunnymark 132 vs 227, endless-runner 226 vs 382, canvasmark 118 vs 212 MB). Fair accounting: WebView counts its separate chromium renderer process (else ~100MB is missed).
- ✅ **CPU: Migo at half or less of WebView (~1.9–2.9×)** — bunnymark 2.6×, endless-runner 2.9×, canvasmark 1.9×. Native GL/Skia is cheaper than the Chromium compositor; also the energy proxy.
- ✅ **Startup: Migo mostly faster** — game-ready (`Fully drawn`) bunnymark 495 vs 697, canvasmark 473 vs 517 ms; endless-runner 710 vs 671 (~6% slower, within single-run jitter).
- = **fps (normal load): near-tie** — Migo ~58 vs WebView 60 (Migo's 1% low slightly lower), consistent across all three.
- 🎉 **canvasmark Canvas2D memory is good** — the earlier debug build sawtoothed to 285MB here (a per-draw GL-resource leak); this round (release + full-screen rendering) Migo holds a stable 118MB (< WebView's 213MB), leak no longer reproduces.
- ✅ **Heavy-load stress back at WebView parity (2026-07-15, fixed by #40)** — the stress regression (100k once 19 vs 32fps) has been located and fixed. Bisection pins the culprit to `4b69dbb` (#36 R1's demand-driven RAF: the compute thread blocks on an eventfd every frame → low utilization → the Kirin990 governor holds the big core at 1546MHz); `4cf93b8` (#40) fixes it by free-running RAF during active animation. Temperature-controlled re-validation (cold-gated to an identical 34.997°C start, per-second all-3-cluster freq sampling, each runtime run twice): Migo #40 ties WebView across the whole curve and edges ahead at high load (**100k 32 vs 31, 180k 18 vs 15**), reproduced twice. See **§8**.

> Note: high-end phone (Kirin 990). At normal load Migo leads on most metrics; low-end devices (the GTM wedge) should widen the memory/startup gaps — the key next test.

## 2. Test matrix (device × game)

| Tier \ game | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **High-end** · Huawei Mate30 Pro (Kirin990/8G/A12) | ✅ done | ✅ done | ✅ done |
| **Mid** (~4G, to buy) | 🔜 | 🔜 | 🔜 |
| **Low-end** ⭐ (~2-3G, to buy, GTM wedge) | 🔜 | 🔜 | 🔜 |

> 1 device × 3 games (both render paths: WebGL × 2 + Canvas2D × 1), each verified full-screen/correct on device.
> **Cross-game finding**: at normal load Migo's lead is highly consistent across all three (memory ~40–44%, CPU ~1.9–2.9×) — a stable low baseline-overhead advantage, largely independent of game weight.

## 3. Results: Mate30 Pro × bunnymark (100 sprites, 60s steady)

### 3.1 Memory 🏆 Migo

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS peak | **~227 MB** | **~132 MB** | **Migo ~42% less** |

- Fair accounting: WebView = main process + chromium sandboxed renderer (`webview_pss.py`). Migo is single-process, all counted.
- PSS has ±tens-of-MB jitter; the direction (Migo clearly lower) is robust.

### 3.2 Startup 🏆 Migo

| metric | WebView | Migo | |
|---|---|---|---|
| game-ready (`Fully drawn`, cool) | 697 ms | 495 ms | Migo ~29% faster |

- First-frame (`Displayed`) fires on WebView's blank window (too early) and Migo adds a Launcher→Game hop — not comparable; use game-ready.
- Absolute values have thermal jitter (WebView 697 this round vs 536 last, device warmer); Migo's snapshot restore is steadier (495 ≈ 493).

### 3.3 fps: normal near-tie; heavy-load regressed then **fixed by #40** (root cause = JS thread frequency)

> **✅ Update (2026-07-15)**: the heavy-load regression documented in this section is **fixed by #40 (`4cf93b8`); stress now ties WebView across the whole curve** (100k 32 vs 31). The following is the **pre-fix** record and root-cause bisection, kept as history; current temperature-controlled data is in **§8**.

**Normal load (100 sprites)**: fps median WebView 60 / Migo 58; 1% low 60 / 55.

**Stress curve (in-game deterministic ramp, `--scenario stress`) — pre-#40 record (Migo was behind past 20k sprites)**:

| sprites | WebView fps | Migo fps |
|---:|---:|---:|
| ≤20 000 | 60 | 48–58 |
| 40 000 | 60 | 30 |
| 70 000 | 43 | 28 |
| 100 000 | 32 | 19 |
| 140 000 | 23 | 19 |
| 180 000 | 16 | 14 |

- **A before/after A/B proves this is a real regression introduced by this round's optimizations (NOT a stale rendering artifact)**. Rebuilding the pre-optimization ff29aa4 in the same release config and re-running on device: **ff29aa4's stress is much stronger** (40k: 59 vs 30 now; 100k: **32 vs 19 now**), and ff29aa4's 32@100k matches the older baseline exactly → **the old baseline's "Migo wins stress" was real, and the current version regressed it.**
- **Per-commit bisection proves the culprit is the earlier canvas/EGL refactor (#31–#34), not the named R1/R2/R3 (R2/R3 actually help)**. Cumulative 100k-fps chain: **ff29aa4 32 → #31–33 (canvas refactor) 19 → #34 (+EGL recovery) 14 → +#36/R1 14 → +R2/R3 (#38) 19**. The big regression happens in #31–34, before R1/R2/R3; R2/R3 recover a chunk (14→19). See §7.
- **The bottleneck is the JS thread's per-frame work; the #31–34 refactor (canvas2d bypass evaluation, Phaser sub-surface handling, EGL context-loss checks) accumulated fixed per-frame cost**. Device-side diagnostics (Huawei blocks `perf_event`): at 100k Pixi emits only 6–7 GL commands and the render thread executes in only 5–8ms/frame, yet the whole frame is 49–140ms → the render thread waits for JS; all builds mali GPU 3–5% (idle), so JS-bound and not confounded by render resolution.
- **Next step**: profile the current per-frame JS/render_thread hot path and trim the fixed per-frame cost these refactors left (keep R2/R3 — they help); heavy-load throughput should return to ff29aa4 levels.
- Real mini-games run at hundreds–thousands of sprites (normal load, where Migo's steady state wins); 20k+ is a synthetic extreme. This curve is a genuine weakness the framework surfaces — not hidden.

### 3.4 CPU 🏆 Migo

| metric | WebView | Migo | delta |
|---|---|---|---|
| CPU (multi-core) | **~118%** | **~46%** | **Migo ~2.6× less** |

- Method: `/proc/<pid>/stat` (utime+stime) delta, WebView includes the renderer. Median of multiple windows + screen-wake before sampling (rejects the occasional bad window).

### 3.5 Energy (proxy)

EMUI disables the fuel gauge + per-uid batterystats + USB power masks drain → CPU is the energy proxy (at fixed fps, CPU is the main driver) → Migo lower. Real energy pending a non-Huawei device / unplugged run / external meter.

## 3.6 Second game: endless-runner (Phaser)

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS peak | **~382 MB** | **~226 MB** | **Migo ~41% less** |
| CPU (multi-core) | **~127%** | **~44%** | **Migo ~2.9× less** |
| game-ready | 671 ms | 710 ms | ~6% slower (within jitter) |
| fps median / 1% low | 60 / 60 | 58 / 55 | near-tie |

WebView portrait fit-scale, Migo native landscape (see §0) — both render the whole game at the same pixel budget.

## 3.7 Third game: canvasmark (Canvas2D) — the real comparison, after fixing a rendering bug

Canvas2D path (not WebGL). **This round fixed the Migo Canvas2D "only 1/9 of the screen" bug (see §0)**, so both now render full-screen and the numbers are comparable:

| metric | WebView | Migo | reading |
|---|---|---|---|
| **PSS memory** | **~213 MB (stable)** | **~118 MB (stable)** | **Migo ~44% less ✅** |
| CPU (multi-core) | **160%** | **83%** | **Migo ~1.9× less** ✅ (smaller than the earlier corner-rendering 2.4× = honest now that Migo renders the full canvas; Canvas2D is heavier than WebGL both sides) |
| fps median / 1% low | 60 / 60 | 58 / 57 | near-tie ✅ |
| game-ready | 517 ms | 473 ms | Migo ~9% faster ✅ |

**The memory leak no longer reproduces**: the earlier debug build sawtoothed to ~285MB here (a locked GL resource leaked per Canvas2D fill); this round (release + full-screen rendering) Migo holds a stable 118MB, well below WebView's 213MB. fps stays ~58.

## 4. Measurement method (system-level, app-agnostic, auditable)

- **Memory**: `dumpsys meminfo`; WebView sums main + `:sandboxed_process`.
- **Startup**: system `am` `Displayed` + `Fully drawn`; no app-log parsing.
- **fps**: prefer SurfaceFlinger `--latency`; this EMUI device blocks it (all zeros) → fall back to the game's rAF telemetry (same both sides), each row records `fps_source`.
- **CPU**: `/proc/<pid>/stat` delta (WebView includes the renderer); **median of multiple windows + screen-wake before sampling** (a single window occasionally reads absurdly low).
- **Stress**: in-game deterministic sprite ramp (Pixi ticker, identical both sides).
- **Orientation**: WebView locked portrait (renders correctly); Migo per game.json (endless = landscape) — both render the whole game at the same pixel budget (see §0).
- **Stability**: force screen-on (`svc power stayon`) before capture.
- **Thermal**: Kirin 990 throttles when hot; both sides measured back-to-back with per-game cooldown (this round 32–35°C); relative comparison is fair, absolute values need a cool reproduction.

## 5. Reproduce

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo release AAR (shipping config; the bench needs an extendable API so release
# requires temporarily disabling library minify): scripts/build-aar.sh release arm64-v8a
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-release.aar
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview

# Temperature-controlled stress A/B (cold-gates both runtimes to an identical cool
# start + samples all 3 clusters' freq + runs each twice; see §8):
bash scripts/stress-ab.sh <SERIAL> <path/to/migo-release.aar>
```

Baseline `baselines/mate30.csv` (this round: release + rendering fixes); old debug baseline backed up at `baselines/mate30.debug-ff29aa4.bak.csv`.

## 6. Diff vs old version (debug / ff29aa4)

| item | old (debug) | this round (release, rendering fixed) |
|---|---|---|
| build | debug (opt-0, distorted) | **release (opt-z + LTO, shipping)** |
| canvasmark rendering | Migo drew only 1/9 of the screen (unnoticed) | **fixed = full-screen, comparison now valid**; CPU 2.4×→**1.9×** (honest) |
| endless-runner WebView | forced landscape = blank | **locked portrait = renders correctly** |
| CPU sampling | single 3s window (occasional 6%/18%) | median + screen-wake |
| memory | "33%→61%, widening" | **consistent ~40–44%** |
| canvasmark memory | Migo worse (leak) | **Migo better (leak gone, still −44% at full-screen)** 🎉 |
| stress heavy-load | Migo ~1.9× stronger (**real, not an artifact**) | regressed (100k 32→19), **fixed by #40 back to parity** (100k 32 vs webview 31). Culprit = `4b69dbb` (#36 R1 demand-RAF); #40 free-run RAF fixes it. See §8 |

## 7. Before/after A/B (NEW = 8b5a704 with R1/R2/R3 vs PREV = ff29aa4 pre-optimization, same release config, device, session)

To verify whether this round's optimizations (R1/R2/R3) actually improved performance, the pre-optimization ff29aa4 was rebuilt in the **same release config** and re-run on device. **Confound**: ff29aa4 lacks this round's rendering fixes, so all three games render into a corner (less work) → CPU/memory are not directly comparable; **only startup (cold start) and stress (JS-bound) are rendering-area-independent and comparable.**

| metric | NEW (optimized) | PREV (pre-opt ff29aa4) | verdict |
|---|---|---|---|
| startup bunnymark | 495 ms | 516 ms | ✅ NEW 4% faster (comparable) |
| startup endless | 710 ms | 763 ms | ✅ NEW 7% faster (comparable) |
| startup canvasmark | 473 ms | 481 ms | ✅ NEW 2% faster (comparable) |
| canvasmark PSS | **118 MB** | **297 MB** | ✅ NEW fixed the Canvas2D leak (297→118) |
| **stress 40k fps** | **30** | **59** | 🔴 **PREV ~2× faster (regression)** |
| **stress 100k fps** | **19** | **32** | 🔴 **PREV ~1.7× faster (regression)** |
| CPU / other memory | — | — | ⚠️ rendering-area confounded, omitted |

**Conclusion (honest, mixed)**:
- ✅ **Faster startup** (2–7%) — R1/snapshot etc. improved cold start.
- ✅ **canvasmark Canvas2D leak fixed** (297→118MB) — a real, important improvement.
- 🔴 **Heavy-load throughput regressed; per-commit bisection proves the culprit is the earlier canvas/EGL refactor (#31–#34), NOT the named R1/R2/R3 (R2/R3 actually help)**. Building several intermediate commits in release and running stress, the 100k-fps chain (cumulative):

| build (cumulative) | 100k fps | step |
|---|---|---|
| ff29aa4 (no optimizations, baseline) | **32** | — |
| #31–33 (canvas2d-bypass / File-perf / canvas-sub-surface) | **19** | 🔴 −13 (biggest chunk) |
| #34 (+EGL context-loss recovery) | **14** | 🔴 −5 |
| 6dbb4b4 (+#36 R1/RAF + perf) | **14** | 0 |
| 8b5a704 (+R2/R3 #38, all opt) | **19** | ✅ +5 (R2/R3 recover) |

All builds are JS-bound (per-thread CPU: JS thread ~100%, mali GPU only 3–5% idle) — not confounded by render resolution. **The big regression is cumulative and comes from the #31–#34 canvas/EGL refactor (extra per-frame bypass evaluation / sub-surface handling / context-loss checks), not the named R1/R2/R3 optimizations; R2/R3 (#38) actually pull throughput back up.** This also **corrects this page's three earlier claims** ("V8 inherently slow / artifact" → "R2 is the culprit" → "R1/R3 is the culprit") — the real culprit is the #31–34 refactor. (#32 alone can't run the current game.js = snapshot/WebGL-method incompatibility, so #31–33 wasn't split further.)
- **Net**: at normal load Migo wins across the board, starts faster, and the leak is fixed; but the **#31–34 refactor accumulated per-frame overhead** that hurts at the 20k+ extreme. Next: profile the current per-frame JS/render_thread hot path and trim the fixed per-frame cost these refactors left behind (keep R2/R3 — they help); heavy-load throughput should return to ff29aa4 levels.

> **Follow-up (see §8): §7's direction was broadly right (the refactors did depress heavy-load throughput), but the precise culprit was not #31–34 — it was #36's `4b69dbb` (demand-driven RAF), now fixed by #40 back to WebView parity.**

## 8. ✅ Heavy-load regression fixed: #40 restores WebView parity (2026-07-15, temperature-controlled)

The stress regression documented in §3.3 / §6 / §7 has been **located and fixed**.

**Precise culprit = `4b69dbb` (#36 R1, "demand-driven vsync/RAF")**. It added a strict 1:1 demand-latch to RAF: the compute thread (the game thread that runs JS+native in the bench) blocks on an eventfd every frame waiting for the next vsync. At moderate load (40–100k) it's <100% busy → the Kirin990 util-driven governor holds the big core at **1546MHz** (instead of 2861) → the same JS runs ~1.8× slower → dropped frames, a "slower→wait→low-util→low-freq→slower" vicious cycle. (§7's attribution to #31–34 was directionally close but imprecise; per-commit bisection nails it to 4b69dbb.)

**Fix = `4cf93b8` (#40, merged to master)**: during active animation let RAF **free-run** (a per-session-constant ticket + signal on every scheduled vsync unconditionally), so the compute thread no longer blocks per frame → utilization returns to ~100% → the governor ramps to 2861MHz, restoring the pre-#36 behavior. The cost is giving up the on-demand-vsync idle-power win, but after the warm window it still returns to idle-stop (idle power unchanged).

**Method** (the strict version of this page's methodology, removing this SoC's #1 confound = load-dependent thermal throttling): master `4cf93b8` rebuilt release / full / arm64 (library minify temporarily off to dodge the R8 inheritance gotcha). Both runtimes are **cold-gated** to an identical **34.997°C** start (`soc_thermal ≤ 35°C` AND `cpu7 scaling_max` back to full 2861MHz before launch), all-**3-cluster** freq + SoC temp sampled per second, `force-stop` after each case, **each runtime run twice**.

| sprites | WebView (r1/r2) | Migo #40 (r1/r2) | Migo/WebView |
|---:|---:|---:|---:|
| 40 000 | 60 / 60 | 58 / 59 | 0.97× |
| 70 000 | 41 / 43 | 45 / 45 | 1.07× |
| 100 000 | 31 / 31 | 32 / 32 | 1.03× |
| 140 000 | 22 / 22 | 23 / 23 | 1.05× |
| 180 000 | 15 / 16 | 18 / 17 | 1.13× |
| 220 000 | 13 / 13 | 13 / 13 | 1.00× |

knee (≥55fps) is **40 000** on both. **Migo #40 ties WebView across the whole curve and edges ahead at high load, reproduced twice** (vs 100k once 19fps before #40 → 32fps now).

**Parity is genuine, not a thermal artifact**: at 220k (both 13fps) WebView pins the big cluster (cpu6/7) at **2855MHz (near max, NOT throttled)** yet only ties Migo; meanwhile Migo **spreads work across all three clusters** (big 2072 / mid 1752 / little 1202 — multi-threaded render/upload/JS on separate cores) and runs **cooler** (tail SoC 62.4 vs WebView 66.1°C). → the pre-#40 "freq-normalized ~1.4× more per-frame CPU work" no longer holds; Migo now reaches equal fps at equal-or-lower temperature. (Cross-core-count "total work" isn't precisely comparable; this is a directional claim.)

**Reproduce**: `scripts/stress-ab.sh <SERIAL> <path/to/migo-release.aar>` (built-in cold gate + 3-cluster freq sampling + two runs each, prints the curves).
