#!/usr/bin/env bash
# pack-game.sh — copy ONE game's static payload into a benchmark shell's assets.
#
# Both the WebView baseline and Migo must run the EXACT same files, so this
# script is the single source of truth for "what got packed". It copies a
# game directory (containing index.html + assets) into the target shell's
# asset location, replacing whatever was there.
#
# Usage:
#   bench/scripts/pack-game.sh <target> <game-src-dir> [--entry <index.html>]
#
#   <target>        webview | migo
#   <game-src-dir>  directory holding the game's static build (has index.html,
#                   or pass --entry to point at it explicitly)
#
# Examples:
#   # vanilla single-file / static game (e.g. cloned 2048 build)
#   bench/scripts/pack-game.sh webview /home/wkspace/opensource/2048
#
#   # a game whose runnable output is under dist/
#   bench/scripts/pack-game.sh webview /home/wkspace/opensource/phaser3-typescript/dist
#
# After packing the WebView target, build + install:
#   (cd bench/webview-shell && ./gradlew :app:assembleRelease)
#   adb install -r bench/webview-shell/app/build/outputs/apk/release/app-release.apk
#
# For the migo target this stages assets under bench/out/migo-assets/<...>; wire
# them into the Migo demo app's asset pipeline (the demo loads game.js / an
# index per its own build — see platforms/android sample). Migo packing is a
# staging convenience, not a full app build (the Migo demo lives in a separate
# repo, minigame-labs/migo-android-demo).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

TARGET="${1:-}"
SRC="${2:-}"
ENTRY=""
shift $(( $# >= 2 ? 2 : $# )) || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --entry) ENTRY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$TARGET" || -z "$SRC" ]]; then
    sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi
if [[ ! -d "$SRC" ]]; then
    echo "ERROR: game source dir not found: $SRC" >&2; exit 2
fi

# Resolve the entry HTML so we can verify the payload is runnable.
if [[ -z "$ENTRY" ]]; then
    if [[ -f "$SRC/index.html" ]]; then
        ENTRY="$SRC/index.html"
    else
        # Pick the shallowest index.html under SRC.
        ENTRY="$(find "$SRC" -name index.html -printf '%d %p\n' 2>/dev/null \
                  | sort -n | head -1 | cut -d' ' -f2-)"
    fi
fi
if [[ -z "$ENTRY" || ! -f "$ENTRY" ]]; then
    echo "ERROR: no index.html found under $SRC (pass --entry <path>)" >&2
    exit 2
fi
# The directory that actually holds the runnable game (entry's parent).
GAME_ROOT="$(cd "$(dirname "$ENTRY")" && pwd)"
echo "[pack] entry:     $ENTRY"
echo "[pack] game root: $GAME_ROOT"

case "$TARGET" in
    webview) DEST="$REPO_ROOT/bench/webview-shell/app/src/main/assets/game" ;;
    migo)    DEST="$REPO_ROOT/bench/out/migo-assets/game" ;;
    *) echo "ERROR: target must be 'webview' or 'migo', got '$TARGET'" >&2; exit 2 ;;
esac

echo "[pack] dest:      $DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
# Copy the whole game-root tree (index.html + sibling assets).
cp -a "$GAME_ROOT/." "$DEST/"

# Sanity: dest must have an index.html at its top level now.
if [[ ! -f "$DEST/index.html" ]]; then
    echo "ERROR: packed payload has no top-level index.html — check --entry" >&2
    exit 2
fi

size=$(du -sh "$DEST" | cut -f1)
files=$(find "$DEST" -type f | wc -l)
echo "[pack] OK — $files files, $size into $TARGET shell"
if [[ "$TARGET" == "webview" ]]; then
    echo "[pack] next: (cd bench/webview-shell && ./gradlew :app:assembleRelease)"
fi
