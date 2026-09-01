#!/usr/bin/env bash
# assert-release-aar.sh <migo.aar>
#
# Refuse to measure a debug build.
#
# This is not a style rule. On 2026-08-29 an AAR built `debug` for an unrelated
# check was run through the public matrix and published to RESULTS.md and the
# project site before anyone noticed; both repositories had to be reverted. A
# debug AAR is a different product -- opt-level 0, no LTO, no R8 -- so every
# number taken from one is measuring something this project does not ship.
#
# The AAR states its own build type: `assets/migo/artifacts/slices/*.json`
# carries `"build_type"`, written by the build that produced the bytes. So the
# check asks the artifact rather than the file name, the directory it came from,
# or the flag someone believes they passed.
set -uo pipefail

aar="${1:?usage: assert-release-aar.sh <migo.aar>}"
[[ -f "$aar" ]] || { echo "[release-aar] FAIL no such file: $aar" >&2; exit 1; }

types="$(python3 - "$aar" <<'PY'
import json, sys, zipfile
seen = set()
with zipfile.ZipFile(sys.argv[1]) as z:
    for name in z.namelist():
        if name.startswith("assets/migo/artifacts/slices/") and name.endswith(".json"):
            try:
                seen.add(json.loads(z.read(name))["build_type"])
            except Exception as exc:            # noqa: BLE001 - reported below
                print(f"unreadable:{name}:{exc}")
print("\n".join(sorted(seen)))
PY
)" || { echo "[release-aar] FAIL could not read $aar" >&2; exit 1; }

if [[ -z "$types" ]]; then
    # This is what a debug AAR looks like: `build-aar.sh debug` emits no
    # artifact manifests at all, so "no build_type" and "debug build" are the
    # same observation here. A malformed release AAR would look identical, and
    # neither may be measured, so one message covers both.
    echo "[release-aar] FAIL $aar carries no artifact manifest, so it declares no" >&2
    echo "[release-aar]      build_type. A debug AAR emits none -- that is the usual" >&2
    echo "[release-aar]      cause. An artifact that cannot say what it is must not be" >&2
    echo "[release-aar]      published from either way." >&2
    exit 1
fi
if [[ "$types" != "release" ]]; then
    echo "[release-aar] FAIL $aar is build_type=$(echo "$types" | tr '\n' ',')" >&2
    echo "[release-aar]      A debug build is opt-level 0, no LTO, no R8. Numbers from" >&2
    echo "[release-aar]      one describe a product this project does not ship." >&2
    exit 1
fi
echo "[release-aar] PASS $(basename "$aar") is a release build"
