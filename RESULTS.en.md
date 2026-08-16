# migo-bench Results

> Chinese is the default; see [RESULTS.md](RESULTS.md). English mirror here.
> Raw data: `out/results.csv` (steady), `out/stress_*.csv` (stress curve). Every row carries full provenance (Migo version, device, WebView version, timestamp, `fps_source`).
> Test build: Migo **release** (opt-z + LTO, the shipping config).

## 1. TL;DR

Same game, same device, same interaction. **Migo native runtime (release)** vs **Android System WebView**. Positioning: Migo = the open-source native WebView replacement.

- ✅ **Memory: Migo clearly lower, consistent ~40–45% across all three** (bunnymark 132 vs 227, endless-runner 226 vs 382, canvasmark 118 vs 213 MB). Fair accounting: WebView counts its separate chromium renderer process (else ~100MB is missed).
- ✅ **CPU: Migo at half or less of WebView (~1.9–2.9×)** — bunnymark 2.6×, endless-runner 2.9×, canvasmark 1.9×. Native GL/Skia is cheaper than the Chromium compositor; also the energy proxy.
- ✅ **Startup: Migo mostly faster** — game-ready (`Fully drawn`) bunnymark 495 vs 697, canvasmark 473 vs 517 ms; endless-runner 710 vs 671 (~6% slower, within single-run jitter).
- = **fps (normal load): near-tie** — Migo ~58 vs WebView 60 (Migo's 1% low slightly lower), consistent across all three.
- ✅ **Scales well under heavy load** — stress-tested to 220,000 sprites (far past any real mini-game's normal load), Migo ties WebView across the whole curve and edges ahead at the high end, while running cooler and spreading work across multiple CPU clusters instead of pinning one core near its ceiling. See §4.

> Note: high-end device only so far (Kirin 990). At normal load Migo leads; mid- and low-end devices should widen the memory/startup gaps further — the key next test.

## 2. Test matrix (device × game)

| Tier \ game | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **High-end** · Huawei Mate30 Pro (Kirin990/8G/Android 12) | ✅ done | ✅ done | ✅ done |
| **Mid** (~4G) | 🔜 | 🔜 | 🔜 |
| **Low-end** ⭐ (~2-3G) | 🔜 | 🔜 | 🔜 |

> 1 device × 3 games (both render paths: WebGL × 2 + Canvas2D × 1), each verified full-screen/correct on device.
> **Cross-game finding**: at normal load Migo's lead is highly consistent across all three (memory ~40–45%, CPU ~1.9–2.9×) — a stable low baseline-overhead advantage, largely independent of game weight.

## 3. Results by game

### 3.1 bunnymark (Pixi/WebGL, 100 sprites, 60s steady)

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS peak | 227 MB | 132 MB | Migo ~42% less |
| CPU (multi-core) | 118% | 46% | Migo ~2.6× less |
| game-ready (`Fully drawn`, cool) | 697 ms | 495 ms | Migo ~29% faster |
| fps median / 1% low | 60 / 60 | 58 / 55 | near-tie |

Memory: WebView = main process + chromium sandboxed renderer, summed; Migo is single-process, all counted. CPU: `/proc/<pid>/stat` delta, median of multiple windows.

### 3.2 endless-runner (Phaser/WebGL)

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS peak | 382 MB | 226 MB | Migo ~41% less |
| CPU (multi-core) | 127% | 44% | Migo ~2.9× less |
| game-ready | 671 ms | 710 ms | ~6% slower (within jitter) |
| fps median / 1% low | 60 / 60 | 58 / 55 | near-tie |

WebView portrait fit-scale, Migo native landscape (per game.json) — both render the whole game at the same pixel budget.

### 3.3 canvasmark (Canvas2D)

| metric | WebView | Migo | delta |
|---|---|---|---|
| PSS memory (stable) | 213 MB | 118 MB | Migo ~45% less |
| CPU (multi-core) | 160% | 83% | Migo ~1.9× less |
| game-ready | 517 ms | 473 ms | Migo ~9% faster |
| fps median / 1% low | 60 / 60 | 58 / 57 | near-tie |

Canvas2D (not WebGL) is heavier on CPU than WebGL on both sides, so the lead here is smaller than the other two games — expected.

## 4. Scaling under heavy load

At normal load (hundreds of sprites, typical for a real mini-game) fps is a near-tie on both sides. To see how each runtime scales under extreme load, an in-game deterministic sprite ramp pushes load up to 220,000 sprites (far past any real mini-game), each stage cold-gated to an identical starting temperature and run twice:

| sprites | WebView fps (2 runs) | Migo fps (2 runs) | Migo/WebView |
|---:|---:|---:|---:|
| 40 000 | 60 / 60 | 58 / 59 | 0.97× |
| 70 000 | 41 / 43 | 45 / 45 | 1.07× |
| 100 000 | 31 / 31 | 32 / 32 | 1.03× |
| 140 000 | 22 / 22 | 23 / 23 | 1.05× |
| 180 000 | 15 / 16 | 18 / 17 | 1.13× |
| 220 000 | 13 / 13 | 13 / 13 | 1.00× |

The knee (fps drops below 55) is at ~40,000 sprites on both sides. **Migo ties WebView across the whole curve and edges ahead at the high end** — and does it at a lower thermal cost: at the 220k extreme, WebView pins its big cluster near max frequency (2855MHz) just to tie, while Migo spreads the work across all three CPU clusters (big/mid/little handling render, upload, and JS in parallel) and runs cooler overall (tail SoC 62.4°C vs WebView's 66.1°C).

Method: both runtimes are cold-gated to an identical starting temperature (≤35°C, big cluster back to full frequency) before each run, with per-second frequency and SoC temperature sampling across all three CPU clusters, each stage run twice to confirm consistency. Reproduce in §7.

## 5. Measurement method (system-level, app-agnostic, auditable)

- **Memory**: `dumpsys meminfo`; WebView sums main + `:sandboxed_process`.
- **Startup**: system `am` `Displayed` + `Fully drawn`; no app-log parsing. Uses game-ready (`Fully drawn`) as the fair comparison point — first-frame (`Displayed`) fires on WebView's blank window and isn't comparable.
- **fps**: prefer SurfaceFlinger `--latency`; some devices (including this round's EMUI test device) block it (all zeros) → fall back to the game's own rAF telemetry (identical instrumentation both sides), each row records `fps_source`.
- **CPU**: `/proc/<pid>/stat` delta (WebView includes the renderer); median of multiple windows + screen-wake before sampling (a single window occasionally reads absurdly low).
- **Stress**: in-game deterministic sprite ramp (Pixi ticker, identical both sides).
- **Orientation**: WebView locked portrait (renders in the device's natural orientation); Migo per game.json — both render the whole game at the same pixel budget.
- **Stability**: force screen-on (`svc power stayon`) before capture.
- **Thermal**: SoC throttles under sustained load; both sides measured back-to-back with cooldown between runs — relative comparison is fair; absolute values vary with device thermal state.

## 6. Known limitations / next steps

- Only one high-end device tested so far (Huawei Mate30 Pro, Kirin 990). Mid- and low-end devices are the key next test — expect wider memory/startup gaps on cheaper hardware.
- Energy is currently a CPU-time proxy (the test device's battery-stats interfaces are restricted, blocking direct discharge measurement); real energy numbers are pending a device without that restriction, or an external power meter.
- Absolute latency/temperature values vary with ambient and device thermal state; this page reports same-session, back-to-back relative comparisons.

## 7. Reproduce

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo release AAR (shipping config): scripts/build-aar.sh release arm64-v8a (in the migo repo)
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 --migo-aar local:.../migo-release.aar
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview

# Temperature-controlled stress A/B (cold-gates both runtimes to an identical cool
# start + samples all 3 clusters' freq + runs each twice; see §4):
bash scripts/stress-ab.sh <SERIAL> <path/to/migo-release.aar>
```

Baseline snapshot: `baselines/mate30.csv`.
