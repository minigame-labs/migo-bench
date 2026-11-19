#!/usr/bin/env bash
# resolve-migo-aar.sh <spec> <dest.aar>
#   spec = local:PATH        copy a locally-built AAR
#        | release-tag:TAG   gh release download from minigame-labs/migo-runtime
#        | sha:SHA           checkout that migo commit + build-aar.sh, ONCE
# Writes <dest.aar> and prints the resolved migo_version to stdout.
#
# WHY `sha:` IS CACHED, and why that is a correctness fix rather than a speed
# one. run.sh calls this before EVERY migo run, and bench-matrix.sh's whole
# install discipline rests on the staged AAR being the same bytes each time:
# "Both shells are installed once, up front, and then left alone... the capture
# scripts reinstalled before every run, which resets the app's ART profile, so
# the launches straight after ran without the AOT-compiled code the app has in
# steady state."
#
# The AAR build is NOT byte-reproducible. Two consecutive `build-aar.sh release
# arm64-v8a` runs on the same clean checkout of migo 9e32a309 produced
# 52d34d72ef40f6ba503df729c4e1422d54d81bb1e736e6fc0414986586a83921 and
# e055ff07440bfb153ec0682dd48760177d3b1ec34c78a86eb6627bb0578e0820 (measured
# 2026-09-06). So a `sha:`-anchored matrix rebuilt per cell, staged different
# bytes per cell, and `install_if_changed` reinstalled the migo shell before
# every measured migo run -- while the WebView shell, whose APK never changed,
# kept its profile. A bias landing on exactly one side of the comparison, in the
# spec the docs recommend for a PUBLISHABLE table.
#
# `local:` and `release-tag:` never had this: one copies a fixed file and the
# other downloads fixed bytes. Caching the built artifact makes `sha:` behave
# the same way. The cache is keyed by the commit, which is immutable, and is
# only ever written after a successful release build by this script.
#
# `release-tag:` is cached too, for a plainer reason: it downloaded the AAR again
# before every migo run, ten times for one matrix, the same ~20 MB each time. The
# cached file is used only while it is the bytes the release publishes: the
# release's SHA256SUMS.txt (a few hundred bytes) is fetched on every call and the
# cached AAR held to the digest it names, so a replaced asset is downloaded again
# and a corrupt one is never staged. A cache can be seeded with a copy of the
# release AAR from anywhere -- it is checked the same way.
set -eu
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
    # One universal, multi-ABI AAR per release (migo-<version>-android.aar) --
    # Gradle picks the right .so per device at install time, so there is
    # nothing to select by device ABI any more. A bare '*.aar' pattern would
    # still be ambiguous: match the trailing "-android.aar" segment
    # specifically, and exclude its sidecar attestation file.
    cache="$(cd "$(dirname "$0")/.." && pwd)/out/aar-cache"
    mkdir -p "$cache"
    sha256() { python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
    sums="$(gh release download "$tag" -R minigame-labs/migo-runtime -p SHA256SUMS.txt -O - 2>/dev/null || true)"
    line="$(printf '%s\n' "$sums" | grep -E '^[0-9a-f]{64}  migo-[^ ]+-android\.aar$' | head -1 || true)"
    if [ -n "$line" ]; then
      want="${line%%  *}"; name="${line##*  }"; cached="$cache/$name"
      if [ ! -f "$cached" ] || [ "$(sha256 "$cached")" != "$want" ]; then
        gh release download "$tag" -R minigame-labs/migo-runtime -p "$name" -O "$cached.part" --clobber >&2
        got="$(sha256 "$cached.part")"
        if [ "$got" != "$want" ]; then
          rm -f "$cached.part"
          echo "ERROR: $name from $tag is $got, but the release's SHA256SUMS.txt says $want" >&2
          exit 1
        fi
        mv -f "$cached.part" "$cached"
      else
        echo "[resolve] reusing $name ($cached), which is the $tag release's bytes" >&2
      fi
      cp "$cached" "$dest"
    else
      # A release with no SHA256SUMS.txt: nothing to hold a cached copy to, so download it as before.
      gh release download "$tag" -R minigame-labs/migo-runtime -p '*-android.aar' -O "$dest" --clobber >&2
    fi
    echo "$tag"
    ;;
  sha:*)
    # RELEASE, not debug. This spec exists to anchor a *publishable* table, and
    # a debug AAR is a different product: opt-level 0, no LTO, no R8. It built
    # debug until 2026-09-02, and that is not a hypothetical -- on 2026-08-29 a
    # debug AAR built for an unrelated check was run through the public matrix
    # and published to RESULTS.md and the site before anyone noticed; both
    # repositories had to be reverted. MEASURING.md's release rule is the rule,
    # and this is the one place a tool could quietly break it.
    # The build's own output goes to stderr. This function's stdout IS the
    # return value -- run.sh captures it as `migo_ver` -- so a single stray
    # `echo` from anything called here lands in results.csv as the version
    # field. Until 2026-09-02 the whole AAR build log did exactly that: every
    # `sha:`-anchored row was written as a multi-line record, and the matrix,
    # which takes `tail -1 results.csv`, recorded only its last fragment. The
    # spec the docs recommend for a *publishable* table had therefore never
    # produced a usable row.
    sha="${spec#sha:}"
    cache="$(cd "$(dirname "$0")/.." && pwd)/out/aar-cache"
    mkdir -p "$cache"
    cached="$cache/$sha.aar"
    if [ -f "$cached" ]; then
      # Same commit, same bytes, so the staged APK does not change and the shell
      # keeps the ART profile the previous cell gave it. See the header.
      echo "[resolve] reusing the cached build of $sha ($cached)" >&2
      cp "$cached" "$dest"
      echo "$sha"
      exit 0
    fi
    ( cd "$MIGO_REPO" && git checkout "$sha" -q && bash scripts/build-aar.sh release arm64-v8a ) >&2
    # build-aar.sh names output migo-<product-profile>-<build-type>-<abi>.aar
    # (full-release-arm64-v8a.aar here: default profile, requested build type,
    # the one ABI passed above) -- never a bare migo-release.aar.
    cp "$MIGO_REPO/platforms/android/dist/migo-full-release-arm64-v8a.aar" "$dest"
    # Written only now: a cache populated before the build succeeded would serve
    # a half-written or foreign artifact to every later cell.
    cp "$dest" "$cached"
    echo "$sha"
    ;;
  *)
    echo "ERROR: bad --migo-aar spec: $spec (want local:PATH | release-tag:TAG | sha:SHA)" >&2
    exit 2
    ;;
esac
