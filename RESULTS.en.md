# migo-bench Results

> Chinese is the default; see [RESULTS.md](RESULTS.md). English mirror here.
> Raw data: `out/results.csv` (steady), `out/stress_*.csv` (stress curve). Every row carries full provenance (Migo version, device, WebView version, timestamp, `fps_source`).
> Test build: Migo **release** (opt-z + LTO, the shipping config), host configured as a product would ship it (`setDebugEnabled(false)`).
> **Everything on this page was re-measured on 2026-08-23.** The previously published numbers had three comparability defects — see §5.1. Two favoured Migo, one worked against it; all three are gone.

## 1. TL;DR

Same game, same device, same interaction. **Migo native runtime (release)** vs **Android System WebView**. Positioning: Migo = the source-available native WebView replacement.

- ✅ **Memory: Migo uses 47–61% less** (bunnymark 111 vs 225, endless-runner 201 vs 379, canvasmark 85 vs 220 MB). Fair accounting: WebView counts its separate chromium renderer process (else ~100MB is missed).
- ✅ **CPU: Migo at a third to a half of WebView (2.3–3.0×)** — bunnymark 2.8×, endless-runner 3.0×, canvasmark 2.3×.
- ✅ **Startup: faster on all six measurements** — three games × two metrics. First frame 13–55% faster, game-ready 4–39% faster.
- = **fps: a tie.** Both sides hold a 60 fps median; 1% low is Migo 59, WebView 60.
- = **Heavy load: a tie.** Stressed to 220,000 sprites, the knee is at 40,000 on both sides and the curve is level or 1 fps in Migo's favour.
- ⚠️ **endless-runner game-ready is a tie, not a lead**: Migo 628/633/749 ms across three rounds against WebView 647/658/664. The ranges overlap; calling it "4% faster" overstates it.

> Note: high-end device only so far (Kirin 990). Mid- and low-end devices should widen the memory/startup gaps further — the key next test.

## 2. Test matrix (device × game)

| Device tier \ Game | bunnymark (Pixi/WebGL) | endless-runner (Phaser/WebGL) | canvasmark (Canvas2D) |
|---|---|---|---|
| **High-end** · Huawei Mate30 Pro (Kirin 990 / 8G / Android 12) | ✅ done | ✅ done | ✅ done |
| **Mid** (~4G) | 🔜 | 🔜 | 🔜 |
| **Low** ⭐ (~2-3G) | 🔜 | 🔜 | 🔜 |

## 3. Results by game

Each cell is the **median of three interleaved rounds** (see §5.2); within a round, WebView and Migo run the same game back to back.

### 3.1 bunnymark (Pixi/WebGL)

| Metric | WebView | Migo | Delta |
|---|---|---|---|
| PSS peak | 225 MB | 111 MB | 51% less |
| CPU (multicore) | 127% | 46% | 2.8× less |
| First frame (`Displayed`) | 522 ms | 235 ms | 55% faster |
| Game-ready (`Fully drawn`) | 650 ms | 399 ms | 39% faster |
| fps median / 1% low | 60 / 60 | 60 / 59 | tie |

### 3.2 endless-runner (Phaser/WebGL)

| Metric | WebView | Migo | Delta |
|---|---|---|---|
| PSS peak | 379 MB | 201 MB | 47% less |
| CPU (multicore) | 134% | 44% | 3.0× less |
| First frame | 380 ms | 329 ms | 13% faster |
| Game-ready | 658 ms | 633 ms | **tie** (overlapping ranges, see §1) |
| fps median / 1% low | 60 / 60 | 60 / 59 | tie |

WebView renders portrait fit-scaled, Migo natively landscape (per game.json) — both render the whole game at the same pixel budget.

### 3.3 canvasmark (Canvas2D)

| Metric | WebView | Migo | Delta |
|---|---|---|---|
| PSS (steady) | 220 MB | 85 MB | 61% less |
| CPU (multicore) | 171% | 74% | 2.3× less |
| First frame | 377 ms | 233 ms | 38% faster |
| Game-ready | 376 ms | 322 ms | 14% faster |
| fps median / 1% low | 60 / 60 | 60 / 59 | tie |

The Canvas2D path costs both sides more CPU than WebGL, so the CPU lead is smaller here. That is expected.

## 4. Scaling under heavy load

An in-game deterministic sprite ramp pushes the load to 220,000 sprites (far past any real mini-game). Each side runs twice, gated to the same starting temperature:

| Sprites | WebView fps (2 runs) | Migo fps (2 runs) | Migo/WebView |
|---:|---:|---:|---:|
| 40,000 | 60 / 60 | 60 / 60 | 1.00× |
| 70,000 | 43 / 42 | 44 / 45 | 1.05× |
| 100,000 | 31 / 31 | 32 / 32 | 1.03× |
| 140,000 | 23 / 23 | 23 / 23 | 1.00× |
| 180,000 | 16 / 16 | 17 / 17 | 1.06× |
| 220,000 | 13 / 13 | 13 / 13 | 1.00× |

The knee below 55 fps is at 40,000 sprites on both sides. **This is a tie**, with Migo 1 fps ahead at three load levels.

**One earlier claim is withdrawn.** This page used to say Migo runs cooler at 220k (62.4 vs 66.1 °C) by spreading work across three CPU clusters while WebView pins its big core. Re-measuring on 2026-08-23 does not reproduce it: SoC peaks were WebView 62.5/64.6 °C against Migo 64.2/65.1 °C, with Migo marginally *warmer*, and the frequency samples show the governor taking the cluster to 2861 MHz in both runs. The original claim rests on a single measurement, so it is withdrawn.

## 5. Measurement method (system-level, app-agnostic, auditable)

### 5.1 Three comparability defects fixed on 2026-08-23

Before this re-measurement the two sides were not measuring the same thing. All three are fixed; they did not all point the same way:

1. **Game-ready came from different events (favoured Migo).** On the WebView side the game itself calls `AndroidBench.ready()` from its first frame. On the Migo side the shell used the engine's `onGameReady`, which fires when module evaluation finishes — *before* the first frame. The gap measures **32 ms**. Both sides now fire from the same line of the same game: the migo shell injects an `AndroidBench` of its own through a prelude script, routed back to the host over the `gameLog` channel.
2. **The shells were not structurally alike (worked against Migo).** The migo shell was two activities and **re-extracted the whole game bundle from assets on every launch**; the webview shell is one activity reading straight from `file:///android_asset/`. An activity transition and a full copy therefore sat inside every measured launch on one side only. Both are now one activity, and extraction happens once per game version — which is also what a real host does, at install or download time rather than at every launch.
3. **Migo ran in a debug configuration (worked against Migo).** `setDebugEnabled(true)` registers an in-process console ring buffer that the WebView side has no equivalent of. It is now off, matching the shipping configuration.

`setCodeSigningEnabled(false)` stays: WebView verifies nothing per file beyond the APK signature, so per-file integrity checking on one side only would measure a feature the other does not have.

### 5.2 Interleaving (why cross-session comparisons do not hold)

Device state drifts. The same unmodified WebView shell read anywhere from **380 to 524 ms** across one night of testing — not thermal throttling (SoC 36.9 °C, battery 34 °C), but slow drift in device state. **Any A/B taken across sessions is untrustworthy.**

Every steady-state number on this page comes from interleaved measurement: one round is WebView and Migo back to back on the same game, three rounds, median per cell. The stress curve additionally uses a temperature gate (§4).

### 5.3 Per-metric definitions

- **Memory**: `dumpsys meminfo`; for WebView, main process + `:sandboxed_process`.
- **Startup**: the system's own `am` `Displayed` and `Fully drawn`, never app-log parsing. First frame (`Displayed`) means different things on the two sides — WebView paints a blank window first — but both numbers are listed.
- **fps**: SurfaceFlinger `--latency` where available; some devices (the EMUI build under test) return all zeros, in which case the game's own rAF telemetry is used (identical on both sides). Every row records its `fps_source`.
- **CPU**: `/proc/<pid>/stat` deltas (WebView includes its renderer process), median over several windows.
- **Orientation**: WebView locked portrait, Migo native per game.json — both render the whole game at the same pixel budget.
- **Stability**: screen forced on before capture (`svc power stayon`).

## 6. Integration cost (what a host pays when a user never opens a mini-game)

A minimal host app, three integrations, single ABI (arm64-v8a), Mate30 Pro, median of five cold starts:

| Integration | APK added | Host cold start | Resident memory |
|---|---:|---:|---:|
| No Migo (baseline) | — | 280 ms | 35.4 MB |
| Full AAR | **+44.8 MB** | **0 ms** (277 ms) | **+1.1 MB** (36.5 MB) |
| Full AAR, host calls `MigoRuntime.getInstance()` | +44.8 MB | **0 ms** (278 ms) | +1.1 MB |
| `-nojni` AAR (engine delivered on demand) | **+0.23 MB** | **0 ms** (280 ms) | +1.1 MB |

- APK added is the **on-disk** size (`.so` is stored uncompressed in an APK); the **download** delta is about +17 MB.
- Cold start is unchanged and memory grows by roughly the SDK's dex alone, because the engine is not loaded until something actually needs it — even once the host holds a `MigoRuntime`.
- `-nojni` is the same build with `jni/**` removed. The engine is delivered by the host the first time a user opens a mini-game, and verified against the manifest the AAR embeds.

## 7. Known limitations / next steps

- One high-end device so far (Huawei Mate30 Pro, Kirin 990). Mid- and low-end are the key next test.
- Energy uses CPU as a proxy (the test device's battery-stats interface is restricted); real power needs a device without that restriction or an external meter.
- Absolute numbers move with device state; what this page gives is a within-round, back-to-back comparison (§5.2).
- endless-runner game-ready is inside the noise and should not be cited as a lead (§1).

## 8. Reproduce

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools
# Migo release AAR (shipping config): scripts/build-aar.sh release arm64-v8a (in the migo repo)

# Interleaved: both sides back to back within a round, three rounds, median per cell (§5.2)
for round in 1 2 3; do for g in bunnymark canvasmark endless-runner; do
  bash scripts/run.sh --runtime webview --game $g --device <SERIAL> --duration 12 --cold-runs 3
  bash scripts/run.sh --runtime migo    --game $g --device <SERIAL> --duration 12 --cold-runs 3 \
       --migo-aar <path/to/migo-release.aar>
done; done
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview

# Temperature-controlled stress A/B (cool-down gate + three-cluster frequency sampling, 2 runs each; §4):
bash scripts/stress-ab.sh <SERIAL> <path/to/migo-release.aar>
```

Baseline snapshot: `baselines/mate30.csv`.
