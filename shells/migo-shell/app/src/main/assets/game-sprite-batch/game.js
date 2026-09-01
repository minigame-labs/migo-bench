// A Canvas2D sprite load, because none of the other bench games are one.
//
// bunnymark renders through Pixi's WebGL path, endless-runner through Phaser's,
// and this repo's canvasmark variant issues no `drawImage` at all. So the whole
// Canvas2D image path -- the one an engine's 2D fallback and a hand-written
// mini-game actually use -- was unmeasured here, and a change to it could
// neither be credited nor caught.
//
// The scene is deterministic on purpose: fixed lattice, fixed sprites, no clock
// and no random number reaches the drawing, so two runs differ only by the
// runtime. It mixes the shapes a sprite batcher has to tell apart:
//   * long runs of one image at 1:1
//   * a uniformly scaled run of the same image
//   * an image change every 8th row
//   * a non-uniformly scaled sprite every 37th, which no rotate-scale transform
//     can express and which must therefore split a run without moving its
//     neighbours
// A batcher that ignores its own eligibility rules shows up as moved pixels,
// not just as a different number.
const canvas = migo.createCanvas();
const ctx = canvas.getContext("2d");
const W = canvas.width, H = canvas.height;

function load(src) {
    const img = migo.createImage();
    img.src = src;
    return img;
}
const spriteA = load("sprite-a.png");
const spriteB = load("sprite-b.png");

// Sized so the lattice covers a phone screen at ~1500 sprites/frame: enough
// that per-sprite cost dominates, not so many that the GPU becomes the wall.
const COLS = 30, ROWS = 50;

function draw() {
    ctx.fillStyle = "#101014";
    ctx.fillRect(0, 0, W, H);

    let n = 0;
    for (let row = 0; row < ROWS; row++) {
        for (let col = 0; col < COLS; col++) {
            const x = 4 + col * 24;
            const y = 4 + row * 24;
            if (n % 37 === 36) {
                ctx.drawImage(spriteA, 0, 0, 16, 16, x, y, 24, 12);
            } else if (row % 8 === 7) {
                ctx.drawImage(spriteB, 0, 0, 16, 16, x, y, 16, 16);
            } else if (col % 5 === 4) {
                ctx.drawImage(spriteA, 0, 0, 16, 16, x, y, 24, 24);
            } else {
                ctx.drawImage(spriteA, 0, 0, 16, 16, x, y, 16, 16);
            }
            n++;
        }
    }
}

let frames = 0;
let windowStart = 0;
let ready = false;

function loop(t) {
    // Wait for both images: `drawImage` drops an unloaded source silently, so a
    // frame drawn before they arrive renders nothing while still counting as a
    // frame -- which would report a flattering fps for an empty screen.
    if (spriteA.loaded && spriteB.loaded) {
        draw();
        if (!ready) {
            ready = true;
            try {
                if (typeof AndroidBench !== "undefined" && AndroidBench.ready) {
                    AndroidBench.ready();
                }
            } catch (e) {}
        }
        frames++;
        if (windowStart === 0) windowStart = t;
        else if (t - windowStart >= 1000) {
            console.error("fps=" + Math.round((frames * 1000) / (t - windowStart)));
            frames = 0;
            windowStart = t;
        }
    }
    requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
