# migo-bench

Reproducible **Migo vs Android System WebView** benchmarks — the same game, same device,
same interaction script, on both runtimes. The evidence behind Migo's "open-source native
runtime that replaces the WebView" positioning.

> This repo is both a **showcase** (adopters/skeptics can re-run it) and a **regression
> harness** (every Migo optimization/fix re-runs the same comparison against a baseline).
> A credible, reproducible benchmark *is* the marketing artifact — credibility is the sell.

## 📊 结果报告 / Results report

**[RESULTS.md（中文,默认）](RESULTS.md)** · **[RESULTS.en.md (English)](RESULTS.en.md)** —
device × game matrix + per-metric tables (memory, startup, fps + stress curve, CPU, energy).
TL;DR on Mate30 Pro × bunnymark: **memory Migo ~33% less · CPU ~half · under heavy load Migo ~1.9× fps · startup ~par cool / ~2.4× faster when throttled · fps tie at normal load.**
And the payoff finding — on the heavier, **real Phaser game** endless-runner the gaps **widen**: **memory Migo ~61% less · CPU ~1/7 · game-ready ~par · fps tie.** Migo's native cost is near-fixed; WebView's Chromium tax grows with the app, so heavier/more-real games favour Migo more.

## What it measures (and the honest weighting)

- **Headline — consistency & auditability + memory.** Migo bundles ONE runtime → identical
  behaviour everywhere; WebView drifts across OEM/OS/versions. Migo is open, pinnable, fixable;
  WebView is a black box that updates out-of-band. Memory footprint is measurably lower.
- **Supporting — efficiency.** cold-start (game-ready), PSS memory, CPU, energy, size.
- **Report-honestly — throughput.** fps usually ties; never led with. fps is Migo's *control*
  point (tunable, e.g. cap at 30 for battery), paired with energy.

### Measurement sources (system-level, app-agnostic; disclosed)

Every headline metric is read from Android, not the app's self-report. fps uses a **layered**
source recorded per row as `fps_source`:

1. **`dumpsys SurfaceFlinger --latency`** present-timestamps (true displayed rate; works for
   Migo's native SurfaceView and WebView) — auto-detected layer.
2. **Fallback** on restricted OEMs (EMUI/Huawei return all-zeros): the **game's own telemetry
   for BOTH runtimes** (identical instrumentation both sides = fair). Never mix a system source
   for one side with an app source for the other.

cold-start = `reportFullyDrawn()` + `am start -W`. memory = `dumpsys meminfo`.

## Layout

```
games/       game payloads (bunnymark Pixi v8, endless-runner Phaser; browser + Migo builds)
shells/      webview-shell + migo-shell  (symmetric minimal apps, each loads one game directly)
scripts/     lib.sh, capture-*.sh, run.sh, parse.py, resolve-migo-aar.sh
out/         results.csv + raw logs (gitignored except results.csv)
tests/       parse.py fixture tests
```

## Discipline

- WebView baseline is a **modern** shell (compileSdk 34) — never an old template.
- Lead with consistency/memory; report fps honestly (it ties).
- Every result row carries **provenance**: migo version, device, WebView version, harness
  version, timestamp, `fps_source`. Results are tied to an exact Migo version (auditability).

## Reproduction runbook

```bash
export PATH=$PATH:$ANDROID_HOME/platform-tools           # adb
python3 scripts/parse.py --header-only > out/results.csv
# WebView baseline:
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3
# Migo (pin a version: local dev AAR, a release tag, or a git sha):
bash scripts/run.sh --runtime migo --game bunnymark --device <SERIAL> --duration 60 --cold-runs 3 \
     --migo-aar local:$HOME/wkspace/migo/platforms/android/dist/migo-debug.aar
column -t -s, out/results.csv
```

### Milestone-1 result — bunnymark, 100 sprites, Huawei Mate30 Pro (Kirin 990, Android 12 / API 31)

| metric | WebView | Migo | read |
|---|---|---|---|
| **PSS memory** | **~207 MB** | **~118 MB** | **Migo ~43% less.** WebView renders in a *separate* chromium sandboxed process; the harness sums it (main + renderer) — counting only the main process would unfairly undercount WebView by ~100 MB. Migo is single-process. |
| fps (median / 1% low) | 60 / 60 | 60 / 58 | tie (as expected — never the headline) |
| cold-start (system `Displayed`, ms) | 384 | 460 | **WebView faster here** — its system Chromium is pre-warmed/shared; Migo cold-starts its whole runtime (V8 + GL + game). Honest; the low-end tier is where the thesis is tested. |

### Stress scenario — fps-vs-load curve (`--scenario stress`)

```bash
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 48 --migo-aar local:...
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --scenario stress --duration 48
# -> out/stress_{migo,webview}.csv  (runtime,sprites,fps_median)
```

A deterministic **in-game sprite ramp** (500→1k→2k→3k→5k→8k→12k→20k, 5 s each — Pixi-ticker based, identical both sides; `scripts/make-stress-game.sh` generates it from the normal bundle) drives the load while the harness records `bunnies=N fps=M`. fps is plotted against N (the load the system can't know).

Mate30 result — **both hold ~60 fps to 20 000 sprites** (WebView 60 across the board; Migo 58–60). The Kirin 990 doesn't reach either runtime's knee at 20 k, so throughput ties under load here too — a bigger ramp or the low-end tier is where the curves would diverge.

Notes: `fps_source=game-telemetry` on this device — EMUI restricts `dumpsys SurfaceFlinger --latency` (all-zeros), so fps falls back to the game's own counter for BOTH runtimes (symmetric); non-Huawei devices will use SurfaceFlinger. Migo pinned to `migo@ff29aa4`. High-end device → memory is the clear win; cold-start/fps modest — the low-end tier (GTM wedge) is the next test.

## Migo version pinning

The harness takes `--migo-aar <release-tag | local:PATH | sha>` so a WIP fix benches against a
local dev AAR and published numbers pin a release tag. Every result stamps the resolved version.
