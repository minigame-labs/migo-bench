#!/usr/bin/env python3
"""Package the three bench games as Migo game packages, for a release.

    python3 scripts/package-games.py <tag> <output-dir>

One zip per game, <game>-<version>.zip, holding <game>/game.js and
<game>/game.json -- the package the Migo shell installs, read from its assets,
the one source the published results were measured on -- beside this
repository's LICENSE and the third-party notices the game carries. Unpacked, the
directory installs as a game package on any Migo host.

The zips are reproducible: entries in a fixed order, each stamped with the
commit's time rather than the file system's, so the same commit always packages
to the same bytes. SHA256SUMS.txt lists them.
"""

import hashlib
import subprocess
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "shells/migo-shell/app/src/main/assets"

# game -> (installed package directory, third-party notices it must carry)
GAMES = {
    "bunnymark": ("game", [ROOT / "games/bunnymark/LICENSE-pixi"]),
    "endless-runner": ("game-endless-runner", sorted((ROOT / "games/endless-runner/dist").glob("main.*.js.LICENSE.txt"))),
    "canvasmark": ("game-canvasmark", []),
}


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"usage: {sys.argv[0]} <tag> <output-dir>")
    tag, out = sys.argv[1], Path(sys.argv[2])
    if not (tag.startswith("v") and tag[1:].count(".") == 2 and tag[1:].replace(".", "").isdigit()):
        fail(f"the tag must be a release version, vX.Y.Z: {tag}")
    version = tag[1:]

    stamp = int(subprocess.run(["git", "log", "-1", "--format=%ct"], cwd=ROOT, check=True,
                               capture_output=True, text=True).stdout.strip())
    date_time = time.gmtime(max(stamp, 315532800))[:6]  # a zip cannot say before 1980

    out.mkdir(parents=True, exist_ok=True)
    sums = []
    for game, (package, notices) in GAMES.items():
        entries = [(f"{game}/game.js", ASSETS / package / "game.js"),
                   (f"{game}/game.json", ASSETS / package / "game.json"),
                   (f"{game}/LICENSE", ROOT / "LICENSE")]
        if game == "endless-runner" and len(notices) != 1:
            fail(f"endless-runner needs exactly one webpack license banner, found {len(notices)}")
        entries += [(f"{game}/{notice.name}", notice) for notice in notices]
        for _, source in entries:
            if not source.is_file():
                fail(f"{source} is missing")

        archive = out / f"{game}-{version}.zip"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
            for name, source in sorted(entries):
                info = zipfile.ZipInfo(name, date_time)
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                zf.writestr(info, source.read_bytes(), compresslevel=9)
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        sums.append(f"{digest}  {archive.name}")
        print(archive.name)

    (out / "SHA256SUMS.txt").write_text("\n".join(sums) + "\n")


if __name__ == "__main__":
    main()
