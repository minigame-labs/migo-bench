const canvas = migo.createCanvas();
const ctx = canvas.getContext('2d');
let last = '';
function tick() {
  const s = canvas.width + 'x' + canvas.height;
  if (s !== last) { last = s; console.error('[ROTPROBE] surface ' + s); }
  ctx.fillStyle = '#ff00ff'; ctx.fillRect(0, 0, 40, 40);
  migo.requestAnimationFrame(tick);
}
tick();
