# On-device profiling (Migo)

Two different questions, two different tools:

- **"Which JS function is hot?"** — steady-state, per-frame work. V8's `--prof`
  sampling profiler, below. Needs a debug AAR.
- **"Where did the 650 ms of cold start go?"** — the engine already instruments
  its own startup phases; see [Attributing the startup budget](#attributing-the-startup-budget-no-debug-aar-needed).
  Works on a release build.

## JS function-level profiling

Function-level CPU profiling of the Migo runtime on a real device, **without
perf_event** (Huawei/EMUI blocks it, so `simpleperf` fails). Uses V8's built-in
`--prof` sampling profiler (SIGPROF timer based) + a self-contained attributor.

## Run it

```sh
# needs a DEBUG migo AAR in migo-shell (the V8-flag hook is #[cfg(debug_assertions)])
SERIAL=<serial> bash scripts/profile-migo.sh --game game-stress --secs 55
SERIAL=<serial> bash scripts/profile-migo.sh --game game-canvasmark --secs 40
SERIAL=<serial> bash scripts/profile-migo.sh --game game-endless-runner --secs 40
SERIAL=<serial> bash scripts/profile-migo.sh --game game-stress --flags "--trace-deopt"
```

`profile-migo.sh` writes `--prof --logfile=…` into `/data/local/tmp/v8flags.txt`
(read on debug builds by `host_runtime.rs`), launches the game, waits for a
steady state, pulls `v8.log`, then runs `tickparse.mjs`. It disarms the profiler
afterwards. Raw logs land in `out/profile/`.

`tickparse.mjs` (pure node, no d8) does the tick-processor's core job in one
chronological pass over `v8.log`: it tracks live code objects
(`code-creation`/`code-move`) + shared libraries, then per `tick` sample reports
① a **category rollup**, ② **self time** (where the CPU actually was), and
③ **top JS user functions** (topmost JS frame on the stack — finds the running
game function even when the CPU is in interpreter/IC builtins).

> `SO: …/base.apk` = native **libmigo.so** (packed in the APK,
> `extractNativeLibs=false`, so it has no separate mapping): Rust + V8 C++.

## Bottleneck taxonomy (Mate30, 2026-07-13)

Three games exercise three completely different bottleneck classes:

| Game | Engine / path | Dominant cost | Read |
|---|---|---|---|
| `bunnymark-stress` (180k) | WebGL / Pixi | **72% game JS + 14.5% megamorphic IC dispatch**, runtime/GL only ~4% | **JS-bound**: V8 executing Pixi. Hot: `updateTransformAndChildren` 23%, physics loop 22%, `packQuadAttributes` 11%, `set x/y/height` 11%. Lever = stabilize Pixi object shapes → ICs go mono/poly, functions re-optimize. |
| `canvasmark` | Canvas2D | **76% native libmigo.so** (Rust rasterizer), JS ~5% | **native-bound**: the 2D raster is in Rust. JS side is just migo's `02_2d_context.js` (`save`/`restore`/`set fillStyle`). |
| `endless-runner` (@59fps) | WebGL / Phaser | 39% native + 25% distributed Phaser JS + 20% V8 call/baseline builtins; 4.4% IC | **balanced/GL-submit-bound** at target fps. migo's GL command stream (`_submitAndSwap`, `orderedRawOp`) is a visible per-frame slice in *both* WebGL games — a runtime-side target that is **not** bunnymark-specific. |

Takeaways: (1) WebGL-heavy games are limited by V8 running the engine's JS
(megamorphic property access), not by Migo's native/op path. (2) Canvas2D is
limited by the native Rust rasterizer. (3) Migo's per-frame GL command-stream JS
(`00_gl_command_stream.js` / `02_webgl_context.js`) shows up across WebGL games
and is worth micro-optimizing independent of any single game.

## Attributing the startup budget (no debug AAR needed)

`--prof` answers "which JS function is hot", which is the wrong question for a
cold start. For startup, ask the engine — it already instruments its own phases,
and the trace comes out of a **release** build:

```sh
adb shell am start -n com.migo.bench.migo/.BenchGameActivity \
  --es migo_game_id bench --es migo_entry_point game.js \
  --es game_asset game-endless-runner \
  --es migo_log_level info
adb logcat -d -v time | grep -E '\[migo\]|Displayed|Fully drawn'
```

Never pass `migo_log_level` in a measured run — INFO logging is itself a cost.

What the lines give you, and a Mate 30 Pro reading of each (endless-runner,
release, 2026-08-23, cold start ≈ 650–710 ms end to end):

| Line | Reading |
|---|---|
| `pre-JS services` | render thread launched, host state wired — 0.2–0.4 ms |
| `JsRuntime::new` / `Host::new() total` | V8 isolate from the snapshot — 14–22 ms |
| `EGL config selected` → `DeviceCapabilities` | pbuffer context + the 709-entry GLES dispatch table + capability detection — **~50 ms**, and none of it needs a Surface |
| `create_onscreen begin` → `GPU caps ready` | window surface + Skia — 31–44 ms; this part does need the Surface |
| `GPU caps ready: … residual wait Xms` | **`residual wait` is the number that matters.** The first figure is only elapsed time since the budget opened; 0.0 ms residual means GPU bring-up never blocked the host |
| `module loaded` | compiling the game bundle — 10–19 ms for 1.2 MB |
| `module evaluated` | the game's own top-level JS — **217–236 ms**, the single biggest block, and WebView pays it too |
| `[MigoPerf][SyncOp] … blocked V8 Nms` | a sync render op stalled behind the render queue. Phaser's `canvasBitBltShift` feature probe reads `getImageData().data` and costs 17–20 ms *inside* the evaluate window |

Two hypotheses this method has already killed, so you do not have to re-test them:

- **The 43 MB `libmigo.so` is not a startup cost.** `System.loadLibrary("migo")`
  measures **8.5 ms**. mmap is lazy; relocation is cheap.
- **GPU capability detection never blocks.** Every trace shows
  `residual wait 0.0ms`; it overlaps host-thread work by construction.

And one that looked free and was not: moving the surface-independent half of GPU
bring-up before `surfaceCreated` (Migo's `createSessionWarm`) is a **regression**
inside a launch — first frame 369 → 401 ms, game-ready 788 → 838 ms. The ~150 ms
between `onCreate` and `surfaceCreated` is idle on the main thread but not on the
CPU: it is process init, dex loading, layout and a window rotation.

## Gotchas

- **Use freshly generated stress assets.** `game-stress` is generated by
  `make-stress-game.sh` (gitignored). A stray hand-injected microbench
  (`console.error "[microbench] loop2M_ms"`, a 2M-sqrt/frame loop) once
  contaminated a profile as a fake #1 hotspot. If logcat shows `[microbench]`,
  re-run `make-stress-game.sh`.
- Symbolizing *which* Rust function inside `base.apk` needs `nm` on `libmigo.so`
  + the mapping base offset (not yet automated here).
