#!/usr/bin/env bash
# resolve-migo-aar.sh <spec> <dest.aar>
#   spec = local:PATH        copy a locally-built AAR
#        | release-tag:TAG   gh release download from minigame-labs/migo
#        | sha:SHA           checkout that migo commit + build-aar.sh
# Writes <dest.aar> and prints the resolved migo_version to stdout.
set -euo pipefail
spec="${1:?usage: resolve-migo-aar.sh <spec> <dest.aar>}"
dest="${2:?usage: resolve-migo-aar.sh <spec> <dest.aar>}"
mkdir -p "$(dirname "$dest")"
MIGO_REPO="${MIGO_REPO:-$HOME/wkspace/migo}"

case "$spec" in
  local:*)
    src="${spec#local:}"
    cp "$src" "$dest"
    ver="$(git -C "$MIGO_REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "local:${ver}"
    ;;
  release-tag:*)
    tag="${spec#release-tag:}"
    gh release download "$tag" -R minigame-labs/migo -p '*.aar' -O "$dest" --clobber
    echo "$tag"
    ;;
  sha:*)
    sha="${spec#sha:}"
    ( cd "$MIGO_REPO" && git checkout "$sha" -q && bash scripts/build-aar.sh debug arm64-v8a )
    cp "$MIGO_REPO/platforms/android/dist/migo-debug.aar" "$dest"
    echo "$sha"
    ;;
  *)
    echo "ERROR: bad --migo-aar spec: $spec (want local:PATH | release-tag:TAG | sha:SHA)" >&2
    exit 2
    ;;
esac
