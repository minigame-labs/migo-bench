# How to take a number here without fooling yourself

Every trap below cost a wrong published number or a wasted day, on this repo, on
this device. They are written as rules with the evidence attached, because a rule
without its evidence gets deleted by the next person who finds it inconvenient.

The per-run definitions (what "first frame" means, how memory is summed) live in
[RESULTS.md §5.3](RESULTS.md). This page is about the ways a correct-looking
measurement is not measuring what you think.

---

## 1. Both sides must already be warm. A just-installed APK is not steady state.

A freshly installed APK has not been dex-optimised. Its first cold starts are
slower, and — this is the part that makes it dangerous — slower **monotonically**,
not noisily. Six consecutive launches after reinstalling the WebView shell:

```
414 → 371 → 347 → …   settling at 338–360 ms
```

That looks like a clean measurement. It is a warm-up curve.

This is what made the bunnymark startup numbers published before 2026-08-23 wrong:
first frame was given as **522 ms** against a true steady state of **354 ms**, and
game-ready as **650 ms** against **529 ms**. The error was ~170 ms, in Migo's
favour, on the repo's headline game.

Interleaving does not save you here. Interleaving cancels *device* drift, which
affects both sides; this affects **one** side, because only one shell had just
been installed.

> **Rule.** Before recording anything, both shells must be installed and have run
> at least three times each. Discard those runs.

## 2. Do not put an install between two measurements.

Writing a ~360 MB APK perturbs the cold start immediately after it. If you are
A/B-ing two builds by swapping APKs, the swap is inside your measurement window.
Either accept it symmetrically (both variants pay it every round) and say so, or
install once per variant and batch the runs.

## 3. Interleave. Device state drifts more than the effect you are chasing.

The same unmodified WebView shell read anywhere from **380 to 524 ms** across one
night — not thermal throttling (SoC 36.9 °C, battery 34 °C), just slow drift in
device state.

> **Rule.** One round = both runtimes back to back on the same game. Three rounds,
> median per cell. **Never** compare a number taken this hour against one taken
> last hour.

## 4. Gate on temperature, for startup too — not only for the stress curve.

`scripts/stress-ab.sh` waits for the SoC to come down before each case. Startup
measurement deserves the same gate: after a couple of hours of launches this
device reads ~370/790 ms on a game that reads ~220/400 ms cold. Every table on
RESULTS.md is gated to ≤34 °C.

The gate must have a **timeout that reports itself**. A silent "waited forever
then proceeded" turns a gated run into an ungated one that still looks gated.

## 5. A nonexistent game asset fails silently, in both directions.

`bunnymark` **is** the default asset directory `game`. There is no
`game-bunnymark` — `scripts/run.sh` encodes the exception:

```sh
[[ "$GAME" == bunnymark ]] || export GAME_ASSET="game-$GAME"
```

Passing `--es game_asset game-bunnymark` does not error. The WebView shell loads
nothing and therefore never reports ready (reads as `NA`); the Migo shell reports
a plausible-looking number that measures an empty runtime. One of the two failure
modes is loud, the other is not, and the quiet one is the one that gets published.

> **Rule.** Derive asset paths from the runner, never from the game's name.

## 6. Measure the same event on both sides.

Migo's game-ready used to come from the engine's `onGameReady` — which fires when
module evaluation finishes, **before** the first frame — while WebView's came from
the game itself calling `AndroidBench.ready()` in its first frame. Measured gap:
**32 ms**, permanently in Migo's favour.

Both sides now report from the same line of the same game. The Migo shell injects
an `AndroidBench` of the same shape via a prelude script.

> **Rule.** Before trusting a cross-runtime delta, name the exact line of code on
> each side that produces the timestamp. If you cannot, you are not comparing.

## 7. Structural asymmetry hides inside the harness, not the runtime.

The Migo shell was once two Activities, and re-copied the entire game bundle from
assets to `filesDir` on **every** launch. The WebView shell was one Activity
reading straight from `file:///android_asset/`. So every measured Migo launch
carried an Activity transition and a full asset copy that the other side never
paid — a harness artifact charged to the runtime.

> **Rule.** Whenever one side has a step the other does not, either remove it or
> state it in the results. "It's just the demo app" is how it gets published.

## 8. Run the configuration you ship.

Migo was benchmarked with `setDebugEnabled(true)`, which registers a console ring
buffer WebView has no equivalent of. A benchmark should not measure a runtime in
a configuration nobody releases.

`setCodeSigningEnabled(false)` is kept off deliberately, and that is the same
principle pointing the other way: WebView verifies nothing per file beyond the APK
signature, so per-file integrity checking on one side only would measure a feature
the other does not have.

## 9. One observation is not a data point.

RESULTS.md once claimed Migo ran 3.7 °C cooler under stress. It came from a single
run. On re-measurement the direction reversed (Migo 64.2/65.1 °C against WebView
62.5/64.6 °C) and the claim was withdrawn.

Related: how you reduce a series is part of the claim. That temperature figure
also changed sign depending on whether "temperature" meant peak or the mean of the
last N samples — and the two sides had different sample counts (82 vs 71), so the
mean was not even comparable. Say which statistic you used.

> **Rule.** A number that has been observed once goes in your notes, not in
> RESULTS.md.

## 10. A script that skips its work must not exit 0.

`scripts/stress-ab.sh` given a `local:`-prefixed AAR path silently never ran the
Migo side and carried on to produce a report. It now rejects both misuse forms.
`runners/verdict.sh` in migo-conformance had the same shape — a suite that
asserted nothing reported "0 assertions" as success, and stayed dead for three
weeks.

> **Rule.** "Did no work" and "did the work" must not produce the same exit code.

## 11. Verify what is on screen in pixels, not by eye.

Two rendering bugs survived several benchmark rounds because the frames looked
plausible: Migo's canvasmark was drawing 1/9 of the screen, and WebView's
endless-runner was blank in landscape. Both sides now have their full-screen
rendering checked by sampling pixels.

> **Rule.** Before a number counts, prove the game is actually drawing the whole
> frame. A fast runtime that renders a ninth of the screen is fast for the wrong
> reason.

## 12. "Initialised" is not "worked" — for audio, prove it with sound.

`AudioThread (lazy) started` and `Audio output device: Ok("default")` say a
stream was opened. They say nothing about whether a single frame reached the
speaker, and the difference is invisible in the log.

endless-runner is the trap: it opens an audio context and **ships no audio files
at all** (the bundle is html/js/md/txt, nothing else). So it emits exactly those
lines and stays silent, correctly. A packaging change was once checked against
that and looked verified while nothing had ever played.

`shells/migo-shell/app/src/main/assets/game-audio-probe` exists for this: it
generates a 6-second tone through WebAudio, so the output path runs with no
decoder and no bundled media involved. The device-side tell is the gap between
`AudioThread (lazy) started` and `AudioThread entered idle sleep` — the tone's
duration plus the ~3 s idle timeout if frames flowed, ~3 s flat if they did not.

> **Rule.** Verify audio with a probe that makes a sound, and read the idle-sleep
> gap rather than the "started" line. Then listen to it.

## 13. Keep the front door and the results page in sync.

`README.md`, `README.zh-CN.md` and `assets/headline-*.svg` all carry numbers.
The SVGs are generated — `python3 scripts/make-headline-chart.py` — from a data
block inside that script, which is easy to forget. For a while the README's
headline chart said "Migo faster (2 of 3)" and quoted a memory figure of ~42%
while RESULTS.md said 3 of 3 and 47–61%.

> **Rule.** A re-measurement is not finished until `RESULTS.md`, `RESULTS.en.md`,
> both READMEs, the headline SVGs, and `../migo-www` all say the same thing.

---

## Checklist for a publishable run

1. Both shells built from current source, installed, and run ≥3 times each.
2. No `adb install` between rounds.
3. SoC gated to ≤34 °C before each round, gate outcome logged.
4. Asset names taken from `scripts/run.sh`, not guessed.
5. Both sides' ready signal traced to the same line of the same game.
6. Migo in release config, `setDebugEnabled(false)`.
7. Three rounds interleaved, median per cell, ranges kept — publish the range
   whenever the medians are within ~10%.
8. Full-frame rendering verified by pixels on both sides.
9. Audio, if it is in scope, verified with `game-audio-probe` and actually
   heard — not inferred from "AudioThread started".
10. `RESULTS.md` + `RESULTS.en.md` + both READMEs + headline SVGs + `migo-www`
    updated together, and anything withdrawn is said to be withdrawn.
