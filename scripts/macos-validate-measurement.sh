#!/usr/bin/env bash
# Prove the macOS harness measures what it claims, before a number from it is
# used -- the iOS check (ios-validate-measurement.sh) on a Mac. scripts/macos-ab.sh
# reports CPU and footprint for an arm made of several processes, from `ps` and
# `footprint` readings at the ends of and inside a window; a helper left out, a
# unit misread or a window misplaced would each fail nothing. So the harness is
# run on content whose cost is known -- shells/ios/calibration: idle, an 8 ms
# spin per frame, 256 MiB held -- in both arms, and
# scripts/check_macos_calibration.py compares the readings with the answers.
#
# Usage: macos-validate-measurement.sh --version vX.Y.Z
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAL="$DIR/../shells/ios/calibration"
for kind in busy mem; do
  cmp -s "$CAL/calib-idle/calib.js" "$CAL/calib-$kind/calib.js" \
    || { echo "ERROR: calib-$kind/calib.js differs from calib-idle's" >&2; exit 1; }
done
log="$(mktemp)"
bash "$DIR/macos-ab.sh" "$@" --games "calib-idle calib-busy calib-mem" --rounds 2 --duration 30 | tee "$log"
csv="$(sed -n 's/^\[macos-ab\] .* -> \(.*\.csv\)$/\1/p' "$log" | head -1)"
rm -f "$log"
python3 "$DIR/check_macos_calibration.py" "$csv"
