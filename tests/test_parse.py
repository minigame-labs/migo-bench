import os
import subprocess
import sys

HERE = os.path.dirname(__file__)
PARSE = os.path.join(HERE, "..", "scripts", "parse.py")
FIX = os.path.join(HERE, "fixtures")


def run(*args):
    r = subprocess.run([sys.executable, PARSE, *args], capture_output=True, text=True, check=True)
    return r.stdout.strip()


def header():
    return run("--header-only").split(",")


def test_header_columns():
    cols = header()
    for expected in ("label", "runtime", "fps_source", "first_frame_ms", "game_ready_ms",
                     "cpu_pct", "pss_peak_kb", "fps_median", "fps_1pct_low",
                     "migo_version", "device_model"):
        assert expected in cols, f"missing column {expected}"


def test_row_values():
    cols = header()
    row = run(
        "--label", "bunnymark_migo_mate30", "--runtime", "migo", "--game", "bunnymark",
        "--migo-version", "abc1234", "--fps-source", "game-telemetry",
        "--meta", f"{FIX}/sample_meta.txt", "--mem", f"{FIX}/sample_mem.txt",
        "--fps", f"{FIX}/sample_fps.txt", "--cold-ms", "460",
        "--game-ready-ms", "551", "--cpu-pct", "111",
    ).split(",")
    d = dict(zip(cols, row))
    assert d["label"] == "bunnymark_migo_mate30"
    assert d["runtime"] == "migo"
    assert d["game"] == "bunnymark"
    assert d["device_model"] == "TAS-AN00"
    assert d["migo_version"] == "abc1234"
    assert d["fps_source"] == "game-telemetry"
    assert d["first_frame_ms"] == "460"
    assert d["game_ready_ms"] == "551"
    assert d["cpu_pct"] == "111"
    assert d["pss_peak_kb"] == "117661"
    assert d["fps_median"] == "59"          # median of [58,59,59,60,61]
    assert d["fps_1pct_low"] == "58"        # min for small N


if __name__ == "__main__":
    # Runnable without pytest: `python3 tests/test_parse.py`
    test_header_columns()
    test_row_values()
    print("test_parse: PASS (2/2)")
