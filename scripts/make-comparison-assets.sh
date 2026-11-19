#!/usr/bin/env bash
# Put one game into both shells' assets, the way record-comparison.sh expects it: the same game code on both arms.
#
#   make-comparison-assets.sh <game-package.zip | game-dir> <web-adapter-bundle.js> <asset-name>
#
# The game is a browser build whose entry is game.js and which draws on `globalThis.canvas` (the demo catalog's games
# are: https://migo-dl-1300686048.cos.ap-shanghai.myqcloud.com/demo/catalog/1/catalog.json lists each with its sha256).
#   migo-shell     assets/<name>/game.js = the web adapter's bundle, then the game -- as the kit injects it
#   webview-shell  assets/<name>/index.html + the game unchanged; the page gives the game the canvas the adapter
#                  presents (the view in CSS pixels), so both arms draw the same number of pixels
set -euo pipefail
GAME="${1:?game package or directory}"; ADAPTER="${2:?web adapter bundle}"; NAME="${3:?asset name}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$(mktemp -d)"; trap 'rm -rf "$SRC"' EXIT
if [[ -d "$GAME" ]]; then cp -R "$GAME/." "$SRC/"; else unzip -q "$GAME" -d "$SRC"; fi
[[ -f "$SRC/game.js" ]] || { echo "no game.js in $GAME" >&2; exit 1; }
MIGO="$DIR/shells/migo-shell/app/src/main/assets/$NAME"; WEB="$DIR/shells/webview-shell/app/src/main/assets/$NAME"
rm -rf "$MIGO" "$WEB"; mkdir -p "$MIGO" "$WEB"
cp -R "$SRC/." "$MIGO/"; cp -R "$SRC/." "$WEB/"
{ cat "$ADAPTER"; echo; cat "$SRC/game.js"; } > "$MIGO/game.js"
[[ -f "$MIGO/game.json" ]] || echo '{"deviceOrientation":"portrait"}' > "$MIGO/game.json"
cat > "$WEB/index.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<style>
html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#000}
canvas{display:block;width:100vw;height:100vh;touch-action:none}
/* An Egret game lays its stage out in a container it creates; a page made for Egret gives it the viewport. */
.egret-player{position:absolute;left:0;top:0;width:100vw;height:100vh}
</style></head>
<body><canvas id="c"></canvas>
<script>
var c = document.getElementById('c');
c.width = window.innerWidth; c.height = window.innerHeight;
globalThis.canvas = c;
</script>
<script src="game.js"></script></body></html>
HTML
echo "assets/$NAME in both shells; rebuild and install them before record-comparison.sh"
