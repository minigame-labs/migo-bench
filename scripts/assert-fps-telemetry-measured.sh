#!/usr/bin/env bash
# assert-fps-telemetry-measured.sh
#
# A bench game may not print an fps it did not measure.
#
# `lib.sh`'s capture_fps falls back to parsing `fps=N` straight out of logcat
# when SurfaceFlinger returns no usable rows -- which is the normal case on this
# EMUI device. So a literal in a game's log is not a debug aid, it is a number
# that reaches the published table as if it had been observed.
#
# This is not hypothetical: a fixture added on 2026-09-02 carried
# `console.error('fps=60 ...')` copied from a template, and would have reported
# a flat 60 for a workload that actually ran at 22.
#
# The rule: every `fps=` a bundled game emits must be followed by an expression,
# never by a digit.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS="$DIR/../shells/migo-shell/app/src/main/assets"
TAG='[fps-telemetry]'
failures=0

shopt -s nullglob
for game in "$ASSETS"/*/game.js; do
    # A digit straight after `fps=` inside a string literal is a hardcoded rate.
    if hits="$(grep -nE "fps=[0-9]" "$game")"; then
        echo "$TAG FAIL $(basename "$(dirname "$game")") prints a literal fps:" >&2
        printf '%s\n' "$hits" | sed 's/^/  /' >&2
        failures=$((failures + 1))
    fi
done

if [[ "$failures" -ne 0 ]]; then
    echo "$TAG $failures game(s) print an fps they did not measure." >&2
    echo "$TAG capture_fps parses these out of logcat -- a literal is published." >&2
    exit 1
fi
echo "$TAG PASS every bundled game computes the fps it prints"
