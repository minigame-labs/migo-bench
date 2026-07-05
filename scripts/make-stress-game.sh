#!/usr/bin/env bash
# Generate the `bunnymark-stress` game from `bunnymark` by injecting a
# deterministic, in-game sprite ramp (Pixi ticker based — no setInterval, which
# Migo's adapter doesn't shim) right after the initial addBunnies(START_COUNT).
# Then stage it into both shells' assets. The stress bundles are generated (not
# committed) since they're the normal bundle + a ~250-byte patch.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$DIR/.."

RAMP=';(function(){var st=[2000,5000,10000,20000,40000,70000,100000,140000,180000,220000],i=0,acc=0;app.ticker.add(function(){acc+=app.ticker.deltaMS;if(i<st.length&&acc>=(i+1)*5000){var d=st[i]-bunnies.length;i++;if(d>0)addBunnies(d);}});})();'

mkdir -p "$ROOT/games/bunnymark-stress"
for src in game.js game.bundle.js; do
  python3 - "$ROOT/games/bunnymark/dist/$src" "$ROOT/games/bunnymark-stress/$src" "$RAMP" <<'PY'
import sys
inp, out, ramp = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(inp).read()
a = "addBunnies(START_COUNT)"
i = s.find(a)
assert i >= 0, "anchor not found in " + inp
i += len(a)
if i < len(s) and s[i] == ';':
    i += 1
open(out, "w").write(s[:i] + ramp + s[i:])
PY
done
cp "$ROOT/games/bunnymark/dist/index.html" "$ROOT/games/bunnymark-stress/index.html"

# Stage into both shells (the APKs bundle these at build time).
mkdir -p "$ROOT/shells/migo-shell/app/src/main/assets/game-stress"
cp "$ROOT/games/bunnymark-stress/game.js" "$ROOT/shells/migo-shell/app/src/main/assets/game-stress/game.js"
cp "$ROOT/shells/migo-shell/app/src/main/assets/game/game.json" "$ROOT/shells/migo-shell/app/src/main/assets/game-stress/game.json"
mkdir -p "$ROOT/shells/webview-shell/app/src/main/assets/game-stress"
cp "$ROOT/games/bunnymark-stress/"{index.html,game.bundle.js,game.js} "$ROOT/shells/webview-shell/app/src/main/assets/game-stress/"

echo "generated bunnymark-stress + staged into both shells"
