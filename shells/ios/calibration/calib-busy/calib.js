// Measurement calibration for scripts/ios-ab.sh: content whose cost is known,
// run in both arms, so the harness's CPU and memory figures can be checked
// against an answer fixed in advance (scripts/ios-validate-measurement.sh).
//
//   idle  repaints its canvas, reports fps     -> the floor
//   busy  spins 8 ms in every frame            -> floor + 8/16.67 = 48% of a core
//   mem   also holds 256 MiB it has written to -> floor + 256 MiB of footprint
//
// Every kind repaints one canvas each frame, stepping through dark greys: the
// harness only measures content it has seen drawing, and the repaint is the same
// in all three, so it cancels out of the differences that are checked. The
// kind is set by the file loaded before this one. The one line that differs by
// arm is where the canvas comes from.
(function (kind) {
  var held = null;
  if (kind === 'mem') {
    held = new Uint8Array(256 * 1024 * 1024);
    // Written, not just allocated: an untouched allocation is not footprint.
    for (var i = 0; i < held.length; i += 4096) held[i] = 1;
  }
  var canvas = typeof migo !== 'undefined'
    ? migo.createCanvas()
    : document.body.appendChild(document.createElement('canvas'));
  if (typeof migo === 'undefined') {
    canvas.width = innerWidth * devicePixelRatio;
    canvas.height = innerHeight * devicePixelRatio;
    canvas.style.width = '100vw';
    canvas.style.height = '100vh';
  }
  var ctx = canvas.getContext('2d');
  var frames = 0;
  var last = Date.now();
  function frame() {
    if (kind === 'busy') {
      var until = performance.now() + 8;
      while (performance.now() < until) {}
    }
    frames++;
    // 32 grey levels, one per frame: the harness looks at the screen 0.3 s (18
    // frames) apart, and two colours alternating per frame were the same colour
    // at every look -- a page that is drawing, judged flat.
    var grey = 16 + (frames % 32);
    ctx.fillStyle = 'rgb(' + grey + ',' + grey + ',' + grey + ')';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    var now = Date.now();
    if (now - last >= 1000) {
      console.error('[calib-' + kind + '] fps=' + Math.round(frames * 1000 / (now - last)) +
        (held ? ' held=' + held.length : ''));
      frames = 0;
      last = now;
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})(globalThis.__calibKind);
