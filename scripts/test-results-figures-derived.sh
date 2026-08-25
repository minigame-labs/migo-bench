#!/usr/bin/env bash
# Every published figure must still be the one out/results.csv gives.
#
# On 2026-08-25 the two report files and the raw rows disagreed three ways at
# once, and none of it was visible to a reader:
#
#   * RESULTS.md quoted the 2026-08-24 session in §1 and an older one in its own
#     §3 tables -- one document, two sessions, nothing saying so;
#   * RESULTS.en.md was entirely at the older numbers and still claimed
#     "faster on all six measurements", a sentence RESULTS.md had already
#     retracted in writing, plus a ⚠️ note calling endless-runner game-ready a
#     "thin lead" when that session has it 10% BEHIND -- a published claim with
#     the sign reversed;
#   * endless-runner CPU read 2.9× where the rows give 3.02×.
#
# A number written by hand into prose carries no provenance. The reader cannot
# tell a fresh figure from a stale one and neither can the next editor, so the
# fix is not proofreading -- it is to generate the figures and fail when the file
# stops matching. This is the same move the engine repo made for binary size.
#
# Host-only: reads the CSV and the two reports, runs no benchmark.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0
fail() { printf '\033[0;31mFAIL: %s\033[0m\n' "$*" >&2; failures=$((failures + 1)); }

for spec in "RESULTS.md:cn" "RESULTS.en.md:en"; do
    file="${spec%%:*}"; lang="${spec##*:}"
    [[ -f "$file" ]] || { fail "$file is missing"; continue; }

    for part in headline tables; do
        begin="<!-- derived:BEGIN $part"
        end="<!-- derived:END $part -->"
        if ! grep -qF "$begin" "$file" || ! grep -qF "$end" "$file"; then
            fail "$file has no derived:$part block -- the markers are how this gate
      finds the generated text at all, so removing them removes the check
      rather than the requirement."
            continue
        fi

        # What the file currently holds, between the markers.
        current="$(awk -v b="$begin" -v e="$end" '
            index($0, b) { inside = 1; next }
            index($0, e) { inside = 0 }
            inside { print }
        ' "$file")"

        expected="$(python3 scripts/results-figures.py --markdown "$lang" --part "$part")"

        if [[ "$current" != "$expected" ]]; then
            fail "$file derived:$part has drifted from out/results.csv."
            printf '\n  --- in the file, --- what the rows give:\n' >&2
            diff <(printf '%s\n' "$current") <(printf '%s\n' "$expected") | head -30 >&2
            printf '\n  Regenerate rather than hand-edit:\n' >&2
            printf '    python3 scripts/results-figures.py --markdown %s --part %s\n\n' "$lang" "$part" >&2
        fi
    done
done

# A silent scan is the failure this gate exists to stop, one layer up.
blocks="$(grep -c 'derived:BEGIN' RESULTS.md RESULTS.en.md 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
if (( blocks != 4 )); then
    fail "expected 4 generated blocks across the two reports, found $blocks"
fi

# Dropped rows are reported, never swallowed: a capture that measured nothing
# must not become a published median without anyone seeing it go.
dropped="$(python3 scripts/results-figures.py --json | python3 -c '
import json, sys
for row in json.load(sys.stdin)["dropped_rows"]:
    print("  dropped:", row)')"
[[ -n "$dropped" ]] && { echo "Rows excluded from the published medians:"; echo "$dropped"; }

if (( failures > 0 )); then
    echo "FAIL: published figures do not match out/results.csv ($failures)" >&2
    exit 1
fi

echo "PASS: every published figure is the one out/results.csv gives (4 generated blocks)"
