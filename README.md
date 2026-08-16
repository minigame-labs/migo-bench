# migo-bench

[English](README.md) | [中文](README.zh-CN.md)

Reproducible **Migo vs Android System WebView** benchmarks — the same game, same device,
same interaction script, on both runtimes. The evidence behind Migo's "open-source native
runtime that replaces the WebView" positioning.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/headline-dark.svg">
  <img alt="Migo vs Android System WebView across three games: memory ~42% lower, CPU ~2x lower, startup faster; full data in RESULTS.md" src="assets/headline-light.svg" width="100%">
</picture>

<sub>Mate30 Pro · release build · 3 games (Pixi/WebGL, Phaser/WebGL, Canvas2D) · every bar traces to a pinned Migo version. Full per-metric tables → **[RESULTS.md](RESULTS.md)** (中文) / **[RESULTS.en.md](RESULTS.en.md)**.</sub>

> **Status — Migo is pre-1.0, actively shipping.** Every release since v0.9.0 has published a runnable, attested AAR — reproduce every number yourself with `--migo-aar release-tag:v0.9.3` (or any tag from [minigame-labs/migo/releases](https://github.com/minigame-labs/migo/releases)). This repo is the public, auditable evidence trail behind those numbers.

> This repo is both a **showcase** (adopters/skeptics can re-run it) and a **regression
> harness** (every Migo optimization/fix re-runs the same comparison against a baseline).
> A credible, reproducible benchmark *is* the marketing artifact — credibility is the sell.

## 📊 Results report

**[RESULTS.md（中文,默认）](RESULTS.md)** · **[RESULTS.en.md (English)](RESULTS.en.md)** —
device × game matrix + per-metric tables (memory, startup, fps + stress curve, CPU, energy).
TL;DR on Mate30 Pro, **consistent across all three games** (bunnymark Pixi, endless-runner Phaser, canvasmark Canvas2D), all verified rendering full-screen: **memory Migo ~40–45% less · CPU ~1.9–2.9× less · game-ready mostly faster · fps near-tie (~58 vs 60) at normal load.**
✅ **Heavy-load scaling holds up** — stress-tested to 220k sprites (far past any real mini-game's normal load): Migo ties WebView across the whole curve and edges ahead at the high end (100k 32 vs 31fps, 180k 18 vs 15fps), while running cooler and spreading work across all CPU clusters instead of pinning one core near its ceiling. See RESULTS §4.

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
     --migo-aar local:$HOME/wkspace/migo/platforms/android/dist/migo-release.aar
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
while the harness records `bunnies=N fps=M`. fps is plotted against N. The two curves track
each other across the whole ramp (Migo at parity, edging ahead at high load) — see RESULTS §4.
`scripts/stress-ab.sh` runs this cold-gated with per-cluster frequency logging.

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

## Contact

- Commercial licensing: licensing@minigame-labs.com
- Security reports: see [SECURITY.md](SECURITY.md)
