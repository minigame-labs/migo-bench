# migo-bench

Reproducible **Migo vs Android System WebView** benchmarks — the same game, same device,
same interaction script, on both runtimes. The evidence behind Migo's "open-source native
runtime that replaces the WebView" positioning.

> This repo is both a **showcase** (adopters/skeptics can re-run it) and a **regression
> harness** (every Migo optimization/fix re-runs the same comparison against a baseline).
> A credible, reproducible benchmark *is* the marketing artifact — credibility is the sell.

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
games/       game payloads (bunnymark; browser + Migo builds, MIT)
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

_(Filled once Milestone 1's `run.sh` reproduces the seed data point — see the plan.)_

## Migo version pinning

The harness takes `--migo-aar <release-tag | local:PATH | sha>` so a WIP fix benches against a
local dev AAR and published numbers pin a release tag. Every result stamps the resolved version.
