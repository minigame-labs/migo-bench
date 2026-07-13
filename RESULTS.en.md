# migo-bench Results

> Chinese is the default; see [RESULTS.md](RESULTS.md). English mirror here.
> Raw data: `out/results.csv` (steady state), `out/stress_*.csv` (stress curve). Every row carries full provenance (Migo version, device, WebView version, timestamp, `fps_source`).
> **Methodology change (2026-07 re-run)**: Migo is now built **release** (opt-level "z" + LTO — the shipping config). Previously published numbers were debug (opt-level 0) and are not directly comparable, so this page **supersedes** them. See §6 "Diff vs old".

## 1. TL;DR

Same game, same device, same interaction, on the **Migo native runtime (release)** vs the **Android System WebView**. Positioning: Migo = the open-source native WebView replacement. **Headline is consistency + auditability + memory/CPU/startup efficiency; fps is a near-tie; and we honestly report one heavy-load regression.**

- ✅ **Memory: Migo clearly lower, and consistently ~40% across all three games** (bunnymark 138 vs 235, endless-runner 228 vs 391, canvasmark 137 vs 220 MB) — crucial: WebView's rendering runs in a **separate chromium process**, which must be counted for fairness (else ~100MB is missed).
- ✅ **CPU: Migo ~40% of WebView (~2.4–2.7× less), consistent across all three games** — native GL/Skia is cheaper than the Chromium compositor; also the energy proxy.
- ✅ **Startup: Migo faster** — game-ready (`Fully drawn`) beats WebView on all three (bunnymark 493 vs 536, endless-runner 658 vs 828, canvasmark 469 vs 523 ms).
- = **fps (normal load): near-tie** — Migo ~58fps vs WebView 60fps (Migo's 1% low slightly lower), consistent across all three.
- 🎉 **canvasmark memory leak is fixed** — the previous honest counter-example (Canvas2D leaking a GL resource per fill, memory sawtoothing 150–285MB) is **gone** in this build: measured stable at ~104MB over 42s. See §3.7.
- ⚠️ **Honest heavy-load finding (throughput)** — pushing the synthetic stress test past 20k sprites, **Migo falls behind WebView** (40k: 29 vs 60fps; 100k: 20 vs 31fps). **Root-caused on-device (see §3.3): the bottleneck is the JS side (V8 running Pixi's per-frame update of 100k sprites) — not rendering/GL, not the command stream.** Migo's native GL command execution is only 5–8ms/frame with perfect batching (6–7 GL commands); the gap is V8 executing heavy per-frame JS ~1.5× slower than Chromium's.

> Note: this is a **high-end** phone (Kirin 990). At normal load Migo leads on most metrics; the GTM wedge is **low-end** devices (small RAM, throttle-prone), where memory/startup gaps should widen — low-end is the key next test (see matrix).

## 2. Test matrix (device × game)

| Tier \ game | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **High-end** · Huawei Mate30 Pro (Kirin990/8G/A12) | ✅ done | ✅ done | ✅ done |
| **Mid** (~4G, to buy) | 🔜 | 🔜 | 🔜 |
| **Low-end** ⭐ (~2-3G, to buy, GTM wedge) | 🔜 | 🔜 | 🔜 |

> 1 device × 3 games done (both render paths: WebGL × 2 + Canvas2D × 1).
> **Cross-game finding (corrected this round)**: at normal load Migo's lead is **highly consistent across all three games** (memory ~40%, CPU ~2.4–2.7×), NOT "the gap widens as the game gets heavier" as the previous version claimed — that was a CPU-sampling artifact in the old debug baseline (endless CPU mis-recorded as 18%). The real picture: Migo has a **stable low baseline-overhead advantage** at normal load, largely independent of game weight.
> **Both paths covered**: WebGL (Pixi/Phaser) and Canvas2D (Skia) are both natively implemented in Migo, 60fps — "WebView replacement" is not WebGL-only.

## 3. Results: Mate30 Pro × bunnymark (100 sprites, 60s steady)

### 3.1 Memory 🏆 Migo

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS peak | **~235 MB** | **~138 MB** | **Migo ~41% less** |

- **Fair accounting**: WebView = main process + chromium sandboxed renderer (`dumpsys meminfo <pkg>` counts only the main process, missing ~100MB). Migo is **single-process**, all counted.
- PSS has ±tens-of-MB jitter (GC/system state); multi-run averaging is steadier, direction (Migo clearly lower) is robust.

### 3.2 Startup 🏆 Migo

**Game-ready (system `Fully drawn`, first real game frame → `reportFullyDrawn()`, fair):**

| metric | WebView | Migo | |
|---|---|---|---|
| game-ready (cool) | 536 ms | 493 ms | Migo ~8% faster |

- Cool, Migo is already slightly faster (V8 snapshot offsets native init + no Chromium process spawn). Hot/throttled scenarios (low-end + long play) hurt WebView's Chromium cold start more; historically observed >2× slower (to reproduce cool/hot split; this round reports cool only).
- "First frame (`Displayed`)" fires on WebView's blank window (too early) and Migo has an extra Launcher→Game hop → **use game-ready**.

### 3.3 fps: normal near-tie; heavy-load ⚠️ Migo behind (to fix)

**Normal load (100 sprites):**

| metric | WebView | Migo |
|---|---|---|
| fps median | 60 | 58 |
| 1% low | 60 | 56 |

**Stress curve (in-game deterministic ramp to 220k sprites, `--scenario stress`) — ⚠️ Migo falls behind past 20k sprites**:

| sprites | WebView fps | Migo fps | |
|---:|---:|---:|:---|
| ≤20 000 | 60 | 55–58 | tie |
| **40 000** | **60** | **29** | WebView ahead |
| **70 000** | 41 | 28 | WebView ahead |
| **100 000** | 31 | 20 | WebView ahead |
| 140 000 | 23 | 19 | WebView ahead |
| 180 000 | 15 | 14 | close |
| 220 000 | 12 | 11 | close |

- ≤20k sprites both hold 55–60fps (high-end ceiling). **Past 20k, WebView's Chromium WebGL batching scales better**: at 40k WebView still 60, Migo down to 29. Knee (≥55fps): Migo ~20k, WebView ~40k.
- **⚠️ This differs from the previous (debug) baseline** — the old version claimed Migo led ~1.9× under load (100k: 32 vs 17). Two independent re-runs this round consistently show the opposite (100k: Migo 20, WebView 31; dead stable, not noise). Note: the old "Migo wins stress" was likely an artifact of the pre-wx-fix rendering bug (sprites drawn into only a screen corner), not a true regression.
- **Root-caused on-device = the JS side, not rendering/command-stream**. Huawei blocks `perf_event` (simpleperf unusable), so we used device-side counters: temporary timing logs in the render thread's GL-batch executor showed that at 100k sprites **Pixi emits only 6–7 GL commands/frame (perfect batching, NOT broken) and native GL execution is only 5–8ms/frame**, yet the whole frame is 49–140ms — the render thread spends most of its time **waiting for the JS thread to produce frames**. Per-thread CPU confirms: **the JS execution thread is pinned ~100%+ while the render thread / GPU / main thread are all low**. So the bottleneck is **Migo's V8 running Pixi's heavy per-frame JS (updating 100k sprite positions + writing vertices) ~1.5× slower than Chromium's V8**. **R2 command-stream execution, the wx-way logical DB, and R3 damage are all ruled out by the evidence.**
- **Next step**: pinning the exact V8 cause (JIT tiers not fully enabled / GC pauses / JS-side command encoding) needs profiling — blocked on this Huawei device, so **run simpleperf on a non-Huawei device to flame-graph the JS thread**.
- Real mini-games run at hundreds–thousands of sprites (i.e. "normal load", where Migo's steady-state wins); 20k+ is a synthetic extreme. But this curve is a genuine weakness the framework should surface — not hidden.

### 3.4 CPU 🏆 Migo

| metric | WebView | Migo | delta |
|---|---|---|---|
| CPU (multi-core, may exceed 100%) | **~125%** | **~48%** | **Migo ~2.6× less** |

- Method: `/proc/<pid>/stat` (utime+stime) delta; WebView counts main + chromium renderer (same as memory).
- Sampling is now **screen-wake + median of multiple windows** (see §4) — the previous single-window method occasionally mis-recorded Migo as 6% (landing on the idle window right after fps capture); fixed this round.
- At equal fps, Migo's CPU is about half → lower power (see energy).

### 3.5 Energy (proxy)

Direct on-device energy is constrained here: this EMUI device **disables the fuel gauge** (`current_now` unreadable) and the **per-uid batterystats energy model is unavailable**, plus USB power masks battery drain. **CPU utilization is the energy proxy** (at fixed fps, CPU is the main energy driver) → Migo lower.
Real energy pending: ①non-Huawei device (open fuel gauge) ②unplugged run + charge delta ③external power meter.

## 3.6 Second game: endless-runner (Phaser) — lead matches bunnymark

Second game is a full webpack build of **Phaser 3** (a real mini-game, not a synthetic benchmark), same device/method, 60s steady, landscape (both sides locked to game.json `landscape` for a like-for-like frame):

| metric | WebView | Migo | delta |
|---|---|---|---|
| **PSS peak** | **~391 MB** | **~228 MB** | **Migo ~42% less** |
| **CPU (multi-core)** | **~128%** | **~48%** | **Migo ~2.7× less** |
| game-ready (`Fully drawn`) | 828 ms | 658 ms | **Migo ~21% faster** |
| fps median / 1% low | 60 / 60 | 58 / 56 | near-tie |
| fps source | game-telemetry | game-telemetry | same both sides (EMUI blocks SurfaceFlinger) |

**Cross-game:**

| metric | bunnymark (Pixi) | endless-runner (Phaser) | canvasmark (Canvas2D) |
|---|---|---|---|
| Memory (Migo/WebView) | 138/235 → −41% | 228/391 → −42% | 137/220 → −38% |
| CPU | 48/125 → 2.6× | 48/128 → 2.7× | 74/175 → 2.4× |
| game-ready | 493/536 | 658/828 | 469/523 |
| fps | 58/60 | 58/60 | 58/60 |

**Conclusion (corrected)**: at normal load, Migo's lead is **highly consistent across all three games** (memory ~40%, CPU ~2.4–2.7×, faster startup, near-tie fps). This comes from a **stable low baseline overhead** in the Migo native runtime; WebView's Chromium tax is always higher. The previous claim that "the gap widens from 33% to 61% memory and up to 7× CPU as the game gets heavier" **does not hold** — that was a one-off CPU sampling artifact in the old debug baseline for endless-runner (mis-recorded 18%, same family as the fixed 6%); reliable re-runs give a consistent ~40% / ~2.5×.

> Single-run sampling (same method as bunnymark); the directional gap is robust; absolute values are steadier when averaged. endless-runner fps telemetry = an engine-agnostic rAF counter (identical code injected both sides, `[endless-runner] fps=N`); WebView's game-ready fires via the injected `AndroidBench.ready()` first-frame callback, Migo's via native onGameReady — the **telemetry contract** a new game must satisfy to join this framework.

## 3.7 Third game: canvasmark (Canvas2D) — the previous counter-example is fixed 🎉

Third game exercises a **different render path**: pure Canvas 2D (not WebGL). canvasmark is the 2D version of bunnymark — each frame `save/translate/rotate/fillRect` draws N rotating squares, tap adds sprites, 100 to start. **Migo natively implements Canvas2D (Skia-backed); `getContext('2d')` is a real 2D context, 60fps.**

| metric | WebView | Migo | reading |
|---|---|---|---|
| **PSS memory** | **~220 MB (stable)** | **~137 MB (stable, measured ~104MB flat)** | **Migo ~38% less ✅** |
| CPU (multi-core) | **175%** | **74%** | **Migo ~2.4× less** ✅ (Canvas2D is heavier than WebGL both sides; Migo still saves >half) |
| fps median / 1% low | 60 / 60 | 58 / 57 | near-tie ✅ |
| game-ready | 523 ms | 469 ms | **Migo ~10% faster** ✅ |

**The previous counter-example is fixed 🎉**: in the old debug build Migo's memory here was **higher and unstable** — PSS sawtoothed between ~150–285MB, root-caused (via this framework's bisection) to **Canvas2D leaking ~400 bytes of locked GL resource per fill draw**. **This release re-run shows the leak gone**: Migo canvasmark memory measured stable at ~104MB over 42s (per-6s samples: 103/103/103/103/103/104/103 MB, no sawtooth, no growth), and the 137MB PSS peak is well below WebView's 220MB. The R2/R3/release path resolved this per-draw GPU resource leak.

> This is the framework's value: the previous version honestly reported the counter-example, and this round faithfully verifies it was fixed (the point of README "Regression workflow"). fps stays ~58–60. fps telemetry = the game's rAF counter `[canvasmark] sprites=N fps=M` (same both sides).

## 4. Measurement method (system-level, app-agnostic, auditable)

- **Memory**: `dumpsys meminfo`; WebView sums main + `:sandboxed_process` (`webview_pss.py`).
- **Startup**: system `am` `Displayed` (first frame) + `reportFullyDrawn`/`Fully drawn` (game-ready); no app-log parsing.
- **fps**: prefer `dumpsys SurfaceFlinger --latency` (compositor present timestamps, app-agnostic); **this EMUI device blocks it (all zeros)**, so fall back to the game's own fps telemetry (same code both sides, symmetric), each row records `fps_source`. Non-Huawei devices use SurfaceFlinger.
- **CPU**: `/proc/<pid>/stat` (utime+stime) delta (WebView includes the renderer). **Median of 3 short windows, with a screen-wake before sampling** — a single 3s window occasionally lands on the idle/stall moment right after fps capture and reads absurdly low (once mis-recorded Migo at ~6%); the median rejects that outlier.
- **Stress**: in-game deterministic sprite ramp (Pixi ticker, identical both sides; `make-stress-game.sh`), fps vs sprite count.
- **Orientation parity**: both shells lock orientation to each game's `game.json` `deviceOrientation` (bunnymark/canvasmark portrait, endless-runner landscape) — otherwise one portrait vs one landscape renders different dimensions and isn't comparable.
- **Stability guard**: force screen-on before capture (`svc power stayon`) — a slept screen stops the activity → zero frames/data.
- **Startup-time parsing**: ActivityManager's `Displayed/Fully drawn` is `+868ms` under 1s but `+1s43ms` at ≥1s — parse s/m units or slow starts are dropped.
- **Thermal note**: Kirin 990 throttles when hot. Within a run both sides are measured **back-to-back with per-game cooldown** (this round stayed 29–35°C); relative comparison is fair, absolute values need a cool reproduction.

## 5. Reproduce

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo uses a release AAR (shipping config):
#   scripts/build-aar.sh release arm64-v8a   (in the migo repo; the bench needs an
#   extendable public API, so release requires temporarily disabling library minify)
# Steady:
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-release.aar
# Stress curve:
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
```

```bash
# Compare / regression gate (Migo vs WebView table · or new Migo vs baseline):
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview
python3 scripts/compare.py --results out/results.csv --baseline baselines/mate30.csv --game bunnymark
```

Migo version is pinnable: `--migo-aar local:PATH | release-tag:TAG | sha:SHA` — every result is tied to an exact Migo version (auditable). Baselines live in `baselines/` (updated to release this round); the old debug baseline is backed up at `baselines/mate30.debug-ff29aa4.bak.csv`.

## 6. Diff vs old version (debug / ff29aa4)

This round switched to a **release** build and fixed two measurement bugs, so the numbers supersede the old ones:

| item | old (debug) | this round (release, reliable) | note |
|---|---|---|---|
| build | debug (opt-level 0) | **release (opt-z + LTO, shipping)** | debug machine code isn't optimized → distorted perf |
| CPU sampling | single 3s window | **median + screen-wake** | old method mis-recorded 6%/18% |
| endless CPU | "~7×" | **~2.7×** | the 7× was a sampling artifact |
| cross-game memory | "33%→61%, widening" | **consistent ~40%** | the widening narrative doesn't hold |
| canvasmark memory | Migo worse (leak) | **Migo better (leak fixed)** 🎉 | |
| stress heavy-load | "Migo ~1.9× stronger" | **⚠️ Migo behind; root cause = JS-side V8 ~1.5× slower on heavy JS (not rendering/command-stream)** | >20k sprites; old value likely a pre-fix render artifact |
