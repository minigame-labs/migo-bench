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
The honest counter-example — **canvasmark (Canvas2D path)**: Migo still wins CPU (~half) and ties fps, but **memory is worse** (~150–285 MB churn vs WebView's stable ~221 MB) — a per-draw GPU-resource leak in Migo's Canvas2D path (bisected to ~400 B of locked GL memory per fill draw) that this framework surfaced. A benchmark that only ever flatters its sponsor isn't credible; this one reports where Migo loses too.

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
games/       game payloads (bunnymark Pixi/WebGL, endless-runner Phaser/WebGL, canvasmark Canvas2D)
shells/      webview-shell + migo-shell  (symmetric minimal apps, each loads one game directly)
scripts/     lib.sh, capture-*.sh, run.sh, parse.py, compare.py, resolve-migo-aar.sh
baselines/   pinned reference result rows (regression gate compares new runs against these)
out/         results.csv + raw logs (gitignored except results.csv)
tests/       parse.py + compare.py fixture tests
.github/     host CI (pytest, script lint, webview-shell build, compare self-test)
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

The authoritative numbers, the device × game matrix, and every per-metric table live in
**[RESULTS.md](RESULTS.md)** (中文) / **[RESULTS.en.md](RESULTS.en.md)** — not duplicated here.

### Stress scenario — fps-vs-load curve (`--scenario stress`, bunnymark only)

```bash
bash scripts/run.sh --runtime migo    --game bunnymark --device <SERIAL> --scenario stress --duration 55 --migo-aar local:...
bash scripts/run.sh --runtime webview --game bunnymark --device <SERIAL> --scenario stress --duration 55
# -> out/stress_{migo,webview}.csv  (runtime,sprites,fps_median)
```

A deterministic **in-game sprite ramp** (2k→220k, 5 s per stage — Pixi-ticker based, identical
both sides; `scripts/make-stress-game.sh` generates it from the normal bundle) drives the load
while the harness records `bunnies=N fps=M`. fps is plotted against N. Past ~20k the curves
diverge (native-GL Migo scales ~1.9× better under heavy load) — see RESULTS §3.3.

## Regression workflow — compare against a baseline

The whole point of the framework: **any future Migo fix/optimization re-runs the same capture and
is diffed against a pinned baseline.** `scripts/compare.py` turns two `results.csv` into a verdict.

```bash
# 1) Showcase table — Migo vs WebView for a game (from one results.csv):
python3 scripts/compare.py --results out/results.csv --game bunnymark --vs-webview

# 2) Regression gate — a NEW Migo build vs the committed baseline (same game).
#    Exits non-zero if any metric regressed past --threshold (default 5%) -> gate a PR.
python3 scripts/compare.py --results out/results.csv --baseline baselines/mate30.csv --game bunnymark
```

Metrics carry a direction (memory/CPU/startup lower-better, fps higher-better); a change within
the threshold is treated as single-run noise. Baselines are committed under `baselines/` and
stamped with the Migo version they were captured against. `.github/workflows/ci.yml` runs the
host-side checks (pytest, script lint, the WebView shell build, and a compare self-test) on every
push — real-device capture stays local (a hosted runner has no phone).

## Migo version pinning

The harness takes `--migo-aar <release-tag | local:PATH | sha>` so a WIP fix benches against a
local dev AAR and published numbers pin a release tag. Every result stamps the resolved version.
