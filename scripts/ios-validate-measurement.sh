#!/usr/bin/env bash
# Prove the iOS harness measures what it claims, before a number from it is used.
#
# scripts/ios-ab.sh reports CPU and footprint for an arm made of several
# processes, from Instruments samples it places on a window by timestamp. Each
# of those steps can be wrong without anything failing: a helper process left
# out, CPU time read in the wrong unit, a window that is off by the recording's
# start. So the harness is run on content whose cost is known in advance --
# shells/ios/calibration: idle, an 8 ms spin per frame, 256 MiB held -- in both
# arms, and scripts/check_ios_calibration.py compares the readings with the
# answers. Run it on the device and SDK the numbers will come from.
#
# Usage: ios-validate-measurement.sh --device <id> --udid <UDID> --version vX.Y.Z --team <TEAM>
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAL="$DIR/../shells/ios/calibration"
# One copy of the calibration code, three packages: they must not drift.
for kind in busy mem; do
  cmp -s "$CAL/calib-idle/calib.js" "$CAL/calib-$kind/calib.js" \
    || { echo "ERROR: calib-$kind/calib.js differs from calib-idle's" >&2; exit 1; }
done
log="$(mktemp)"
bash "$DIR/ios-ab.sh" "$@" --games "calib-idle calib-busy calib-mem" --rounds 2 --duration 30 | tee "$log"
csv="$(sed -n 's/^\[ios-ab\] .* -> \(.*\.csv\)$/\1/p' "$log" | head -1)"
rm -f "$log"
python3 "$DIR/check_ios_calibration.py" "$csv"
