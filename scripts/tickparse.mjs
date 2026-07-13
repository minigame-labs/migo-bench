// Attribute V8 --prof samples (v8.log) to JS functions, without needing d8.
//
// Does the tick-processor's core job in a single chronological pass: maintains a
// live code map (code-creation / code-move / code-delete) plus a shared-library
// map, then for every `tick` sample resolves (a) the top frame = self time and
// (b) the topmost JS *user* function on the stack. Also rolls samples up into
// coarse buckets (game JS / Migo runtime / V8 builtin / native .so) so bottlenecks
// outside the game's own code (runtime, GC, IC dispatch) are visible too.
//
// Usage: node tickparse.mjs <v8.log> [topN=30]
import fs from 'fs';

const path = process.argv[2];
const TOPN = Number(process.argv[3] || 30);
if (!path) { console.error('usage: node tickparse.mjs <v8.log> [topN]'); process.exit(2); }
const log = fs.readFileSync(path, 'utf8').split('\n');

const code = new Map();               // startAddr -> {end,name,type}
const libs = [];                      // [{start,end,name}]
const selfM = new Map();              // "TYPE: name" -> ticks (top frame)
const jsM = new Map();                // js user fn name -> ticks (stack)
const bucket = new Map();             // category -> ticks (self)
let jsMissing = 0, totalTicks = 0;

let sortedDirty = true, sortedArr = [];
function rebuild() {
  sortedArr = [];
  for (const [start, o] of code) sortedArr.push([start, o.end, o.name, o.type]);
  sortedArr.sort((a, b) => a[0] - b[0]);
  sortedDirty = false;
}
function findCode(addr) {
  if (sortedDirty) rebuild();
  let lo = 0, hi = sortedArr.length - 1, ans = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    if (sortedArr[mid][0] <= addr) { ans = mid; lo = mid + 1; } else hi = mid - 1;
  }
  if (ans < 0) return null;
  const e = sortedArr[ans];
  return addr < e[1] ? e : null;      // [start,end,name,type]
}
function findLib(addr) {
  for (const l of libs) if (addr >= l.start && addr < l.end) return l.name;
  return null;
}
// Coarse category for a resolved self-frame key, for the rollup.
function categorize(type, name) {
  if (type === 'SO') return name.includes('libc') ? 'native: libc' : 'native: other .so';
  if (type === 'Builtin') {
    if (/IC(_|$)|IC_Mega|IC_Poly/.test(name)) return 'V8 builtin: IC dispatch (megamorphic/poly)';
    return 'V8 builtin: other';
  }
  if (type === 'BytecodeHandler') return 'V8 interpreter (bytecode handlers)';
  if (name.includes('ext:')) return 'Migo runtime JS (ext:)';
  if (name.includes('/games/')) return 'game JS';
  return 'other JS';
}

for (const line of log) {
  if (!line) continue;
  if (line.startsWith('code-creation,')) {
    const f = line.split(',');
    const addr = Number(f[4]), size = Number(f[5]);
    if (Number.isFinite(addr) && size > 0) {
      code.set(addr, { end: addr + size, name: f[6] || '', type: f[1] });
      sortedDirty = true;
    }
  } else if (line.startsWith('code-move,')) {
    const f = line.split(',');
    const from = Number(f[1]), to = Number(f[2]);
    const o = code.get(from);
    if (o) { code.delete(from); code.set(to, { end: to + (o.end - from), name: o.name, type: o.type }); sortedDirty = true; }
  } else if (line.startsWith('code-delete,')) {
    code.delete(Number(line.split(',')[1])); sortedDirty = true;
  } else if (line.startsWith('shared-library,')) {
    const f = line.split(',');
    libs.push({ name: f[1], start: Number(f[2]), end: Number(f[3]) });
  } else if (line.startsWith('tick,')) {
    const f = line.split(',');
    const pc = Number(f[1]);
    const frames = [pc];
    for (let i = 6; i < f.length; i++) frames.push(Number(f[i]));

    const topc = findCode(pc);
    let selfKey, cat;
    if (topc) { selfKey = `${topc[3]}: ${topc[2]}`; cat = categorize(topc[3], topc[2]); }
    else { const l = findLib(pc); selfKey = l ? `SO: ${l}` : 'unknown'; cat = l ? categorize('SO', l) : 'unknown'; }
    selfM.set(selfKey, (selfM.get(selfKey) || 0) + 1);
    bucket.set(cat, (bucket.get(cat) || 0) + 1);

    let jsName = null;
    for (const a of frames) {
      const c = findCode(a);
      if (c && c[3] === 'JS') { jsName = c[2]; break; }
    }
    if (jsName) jsM.set(jsName, (jsM.get(jsName) || 0) + 1);
    else jsMissing++;
    totalTicks++;
  }
}

const top = (m, n) => [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);
const pct = (c) => (100 * c / totalTicks).toFixed(1).padStart(5) + '%';
const shorten = (s) => s.replace(/file:\/\/\/data\/user\/0\/[^/]+\/files\/migo\/games\/[^/]+\/code\//, '');

console.log(`total ticks: ${totalTicks}   (no JS frame on stack: ${jsMissing} = ${pct(jsMissing)})\n`);

console.log('=== ROLLUP (self time by category) ===');
for (const [k, c] of top(bucket, 20)) console.log(`${pct(c)}  ${String(c).padStart(5)}  ${k}`);

console.log('\n=== TOP SELF (top frame = where the CPU actually was) ===');
for (const [k, c] of top(selfM, TOPN)) console.log(`${pct(c)}  ${String(c).padStart(5)}  ${shorten(k)}`);

console.log('\n=== TOP JS USER FUNCTIONS (topmost JS frame on stack) ===');
for (const [k, c] of top(jsM, TOPN)) console.log(`${pct(c)}  ${String(c).padStart(5)}  ${shorten(k)}`);
