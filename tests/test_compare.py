import os
import subprocess
import sys

HERE = os.path.dirname(__file__)
SCRIPTS = os.path.join(HERE, "..", "scripts")
COMPARE = os.path.join(SCRIPTS, "compare.py")
FIX = os.path.join(HERE, "fixtures")
sys.path.insert(0, SCRIPTS)
import compare  # noqa: E402


def run(*args):
    return subprocess.run([sys.executable, COMPARE, *args], capture_output=True, text=True)


# --- unit: direction-aware improvement math -------------------------------------------------

def test_improvement_pct_lower_better():
    # memory 222 -> 150 is a ~32% improvement when smaller is better
    assert round(compare.improvement_pct(222, 150, "low")) == 32
    # 150 -> 222 is a regression (negative)
    assert round(compare.improvement_pct(150, 222, "low")) == -48


def test_improvement_pct_higher_better():
    # fps 40 -> 60 is a +50% improvement when larger is better
    assert round(compare.improvement_pct(40, 60, "high")) == 50
    assert round(compare.improvement_pct(60, 40, "high")) == -33


def test_compare_rows_skips_missing_metric():
    base = {"pss_peak_kb": "227328", "cpu_pct": ""}      # cpu empty on base
    cand = {"pss_peak_kb": "153600", "cpu_pct": "47"}
    names = [m["name"] for m in compare.compare_rows(base, cand, 5.0)]
    assert "pss_peak_kb" in names
    assert "cpu_pct" not in names          # skipped, not invented


def test_compare_rows_verdicts():
    base = {"pss_peak_kb": "227328", "fps_median": "60"}   # 222 MB, 60 fps
    cand = {"pss_peak_kb": "153600", "fps_median": "60"}   # 150 MB, 60 fps
    by = {m["name"]: m for m in compare.compare_rows(base, cand, 5.0)}
    assert by["pss_peak_kb"]["verdict"] == "better"        # 32% less memory
    assert by["fps_median"]["verdict"] == "flat"           # equal fps within band


# --- CLI: modes + exit codes ----------------------------------------------------------------

def test_cli_vs_webview():
    r = run("--results", f"{FIX}/compare_results.csv", "--game", "bunnymark", "--vs-webview")
    assert r.returncode == 0, r.stderr
    assert "PSS memory" in r.stdout and "Migo" in r.stdout
    assert "✅" in r.stdout                                 # memory is a clear win


def test_cli_baseline_no_regression():
    # candidate (results.csv migo) is ~= baseline -> exit 0
    r = run("--results", f"{FIX}/compare_results.csv", "--baseline", f"{FIX}/compare_baseline.csv",
            "--game", "bunnymark")
    assert r.returncode == 0, r.stderr
    assert "no regression" in r.stderr


def test_cli_baseline_regression_gates():
    # candidate regressed (memory +32%, fps down) -> exit 1
    r = run("--results", f"{FIX}/compare_regressed.csv", "--baseline", f"{FIX}/compare_baseline.csv",
            "--game", "bunnymark")
    assert r.returncode == 1, r.stdout + r.stderr
    assert "REGRESSION" in r.stderr


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print("test_compare: PASS")
