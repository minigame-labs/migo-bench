// canvasmark — a Canvas 2D sprite benchmark (the 2D-path analog of bunnymark, which is
// WebGL/Pixi). Pure vanilla Canvas2D: no engine, no CDN, no image assets. Draws N bouncing
// rotating squares per frame via ctx.save/translate/rotate/fillRect — the canvas2d hot path.
// Same code runs on the WebView (native canvas) and on Migo (adapter -> native Skia 2D).
// Tap to add sprites. Emits the bench telemetry contract: `[canvasmark] sprites=N fps=M`.
(function () {
  var canvas = document.getElementById("GameCanvas") || document.querySelector("canvas");
  var W = window.innerWidth || 720;
  var H = window.innerHeight || 1280;
  canvas.width = W;
  canvas.height = H;
  var ctx = canvas.getContext("2d");

  var START_COUNT = 100;      // match bunnymark's default -> fair cross-path comparison
  var TAP_ADD = 100;
  var COLORS = ["#e63946", "#f1faee", "#a8dadc", "#457b9d", "#ffd166", "#06d6a0", "#ef476f"];
  var sprites = [];

  function addSprites(n) {
    for (var i = 0; i < n; i++) {
      sprites.push({
        x: Math.random() * W, y: Math.random() * H,
        vx: (Math.random() * 2 - 1) * 3, vy: (Math.random() * 2 - 1) * 3,
        size: 12 + Math.random() * 16,
        angle: Math.random() * Math.PI * 2, va: (Math.random() * 2 - 1) * 0.12,
        color: COLORS[(Math.random() * COLORS.length) | 0],
      });
    }
  }
  addSprites(START_COUNT);

  function onTap() { addSprites(TAP_ADD); }
  if (canvas.addEventListener) canvas.addEventListener("touchstart", onTap);
  if (document.addEventListener) document.addEventListener("touchstart", onTap);

  var frames = 0;
  var last = (typeof performance !== "undefined" && performance.now) ? performance.now() : Date.now();
  var firstFrame = false;

  function frame() {
    var now = (typeof performance !== "undefined" && performance.now) ? performance.now() : Date.now();
    // First frame -> signal game-ready to the WebView shell (Migo signals natively; here it's a no-op).
    if (!firstFrame) {
      firstFrame = true;
      try { if (typeof AndroidBench !== "undefined" && AndroidBench.ready) AndroidBench.ready(); } catch (e) {}
    }

    ctx.fillStyle = "#12121e";
    ctx.fillRect(0, 0, W, H);
    for (var i = 0; i < sprites.length; i++) {
      var s = sprites[i];
      s.x += s.vx; s.y += s.vy; s.angle += s.va;
      if (s.x < 0 || s.x > W) s.vx = -s.vx;
      if (s.y < 0 || s.y > H) s.vy = -s.vy;
      ctx.save();
      ctx.translate(s.x, s.y);
      ctx.rotate(s.angle);
      ctx.fillStyle = s.color;
      ctx.fillRect(-s.size / 2, -s.size / 2, s.size, s.size);
      ctx.restore();
    }

    frames++;
    if (now - last >= 1000) {
      var fps = Math.round(frames * 1000 / (now - last));
      try { console.error("[canvasmark] sprites=" + sprites.length + " fps=" + fps); } catch (e) {}
      frames = 0;
      last = now;
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();
