// 240 offscreen Canvas2D canvases, each repainted every frame.
//
// 240 rather than 80 for one reason: at 80 both arms sit on the 60 fps vsync
// cap, so the number cannot express a throughput difference -- it can only say
// "occasionally missed a frame". This project has been burned by that before
// (JITLESS.md: three games tied at 60 fps until the cap was lifted, after which
// the same builds differed by 2.4-16x). Above the cap fps becomes a ratio
// again.
//
// Here because this is the shape that costs the most memory in the whole
// engine: an offscreen canvas holds 4.86 MB of Graphics, and 96% of that is
// its own GrDirectContext, not its pixels (128x64 = 32 KB). The attribution is
// in migo's docs/performance/android/multicanvas-fixed-cost.md.
//
// It is a shop UI / label-cache shape, not a game: many small canvases holding
// pre-rendered text. The published matrix has nothing like it, so a change to
// per-canvas fixed cost was previously invisible to this harness.
const N = 240;

const canvas = migo.createCanvas();
const ctx = canvas.getContext('2d');

const offscreens = [];
for (let i = 0; i < N; i++) {
  const c = migo.createCanvas();
  c.width = 128;
  c.height = 64;
  offscreens.push({ c, octx: c.getContext('2d') });
}

let frame = 0;
let fpsWindowStart = 0;

function paint() {
  for (let i = 0; i < offscreens.length; i++) {
    const { c, octx } = offscreens[i];
    octx.clearRect(0, 0, c.width, c.height);
    octx.fillStyle = '#000000';
    octx.fillText('Label ' + i, 4, 24);
  }

  ctx.fillStyle = (frame % 60 < 30) ? '#20c060' : '#1f8f4c';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  frame += 1;
  if (frame === 1) {
    try {
      if (typeof AndroidBench !== "undefined" && AndroidBench.ready) AndroidBench.ready();
    } catch (e) {}
  }
  if (frame % 60 === 0) {
    // A measured rate, never a literal: lib.sh's game-telemetry fallback
    // parses `fps=N` straight out of logcat, so a hardcoded number would be
    // published as if it had been observed.
    const now = Date.now();
    if (fpsWindowStart > 0) {
      console.error('fps=' + Math.round((60 * 1000) / (now - fpsWindowStart))
        + ' [multicanvas-240] frame ' + frame + ', ' + offscreens.length
        + ' offscreen canvases painted');
    }
    fpsWindowStart = now;
  }
  requestAnimationFrame(paint);
}
requestAnimationFrame(paint);
