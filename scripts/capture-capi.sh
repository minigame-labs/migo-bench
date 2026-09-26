#!/usr/bin/env bash
# Capture the C ABI host: the NativeActivity in migo's tests/c_host/android,
# which embeds the engine through the public C headers with no Java of its own.
# Steady fps + CPU + memory only.
#
# Why this arm exists: the C ABI cannot be declared stable while "Android
# performance with no material regression" is open (migo include/migo/README.md,
# ABI v1 freeze blockers). The regression that matters is against the Java SDK,
# the path every Android customer uses today -- so this is measured beside
# capture-migo.sh, same game, same session, same functions from lib.sh.
#
# The APK is built in the migo repo and handed in, not built here:
#   bash scripts/build-android-c-host.sh arm64-v8a --package <extracted
#     migo-<version>-capi-android-arm64.tar.gz>
# links the published package, so the engine bytes are a release's own -- the
# counterpart of the release AAR the migo arm measures.
#
# No startup numbers. The migo shell reports game-ready from the game's own
# `AndroidBench.ready()` through a prelude this host does not inject, and a
# cold start measured to a different event is the §6 trap (MEASURING.md). The
# steady-state instruments are the ones the freeze blocker is about.
#
# Asymmetries against the migo shell, stated rather than hidden (§7): the Java
# shell injects a one-line prelude and a gameLog handler; this host sends one
# scripted gamepad sample at a fixed early frame. Neither runs per frame.
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/lib.sh"

LABEL=""; OUT=""; DUR=60; APK="${CAPI_APK:-}"
while [[ $# -gt 0 ]]; do case "$1" in
  --label) LABEL="$2"; shift 2;; --out) OUT="$2"; shift 2;;
  --duration) DUR="$2"; shift 2;; --apk) APK="$2"; shift 2;;
  --cold-runs|--scenario) shift 2;;   # accepted for run.sh's uniform call; see header
  *) echo "unknown $1" >&2; exit 2;; esac; done
require_one_device
[[ -f "$APK" ]] || { echo "ERROR: no C host APK (--apk or CAPI_APK); build it in migo with scripts/build-android-c-host.sh" >&2; exit 2; }

PKG=com.migo.chost; ACT=android.app.NativeActivity; pfx="$OUT/$LABEL"
CONTENT_ID=bench
# The same bundle the migo shell runs: its assets/<GAME_ASSET or game>.
ASSET_DIR="$DIR/../shells/migo-shell/app/src/main/assets/${GAME_ASSET:-game}"
[[ -f "$ASSET_DIR/game.js" ]] || { echo "ERROR: no game at $ASSET_DIR (§5: a missing asset must fail)" >&2; exit 2; }

install_if_changed "$PKG" "$APK"

# Stage the content only when its bytes changed: a push is a write between two
# measurements, the same perturbation §2 forbids for an install.
CODE="files/migo/games/$CONTENT_ID/code"
for f in game.js game.json; do
  [[ -f "$ASSET_DIR/$f" ]] || continue
  want="$(sha256sum "$ASSET_DIR/$f" | cut -d' ' -f1)"
  have="$("${ADB[@]}" shell "run-as $PKG sh -c 'sha256sum $CODE/$f 2>/dev/null'" | awk '{print $1}' | tr -d '\r')"
  if [[ "$want" != "$have" ]]; then
    "${ADB[@]}" shell "run-as $PKG sh -c 'mkdir -p $CODE && cat > $CODE/$f'" < "$ASSET_DIR/$f"
    echo "[capi] staged $f ($want)" >&2
  fi
done
echo "$CONTENT_ID" | "${ADB[@]}" shell "run-as $PKG sh -c 'cat > files/content-id'"
# WARN, because it is the Java SDK's default level: that is what puts the game's
# console.error fps telemetry on logcat in the migo arm, and this makes the C
# host do the same and nothing more. The fps fallback reads that line on both
# sides; without this the capi arm had none. Higher levels switch on engine
# tracing, which is a cost the other arm does not pay.
echo warn | "${ADB[@]}" shell "run-as $PKG sh -c 'cat > files/log-level'"

provenance_kv "$PKG" > "${pfx}_meta.txt"
echo "capi_apk_sha256=$(sha256sum "$APK" | cut -d' ' -f1)" >> "${pfx}_meta.txt"
"${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true; sleep 2
"${ADB[@]}" shell am start -n "$PKG/$ACT" >/dev/null 2>&1; sleep 8   # same settle as capture-migo.sh
assert_renders "$PKG" >> "${pfx}_meta.txt"
capture_fps "$PKG" "$DUR" "$pfx" >> "${pfx}_meta.txt"
echo "cpu_pct=$(capture_cpu "$PKG")" >> "${pfx}_meta.txt"
capture_mem "$PKG" "${pfx}_mem.txt"
echo "[capi] captured: $(grep -E 'cpu_pct|fps_source' "${pfx}_meta.txt" | tr '\n' ' ')"
