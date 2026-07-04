#!/usr/bin/env python3
"""Fair WebView PSS: sum the app's main process + the chromium sandboxed renderer.

WebView (Chromium) renders in a SEPARATE `<webview-provider>:sandboxed_process*`
process that `dumpsys meminfo <pkg>` does NOT include — counting only the main
process massively undercounts WebView's true footprint. Reads a system-wide
`dumpsys meminfo` on stdin, sums the app package line + the webview sandboxed
renderer line(s) from the "Total PSS by process:" section, and prints
`TOTAL PSS: <kb>` so parse.py's existing reader works unchanged.

Usage:  adb shell dumpsys meminfo | webview_pss.py <app_pkg>
"""
import re
import sys


def main() -> None:
    pkg = sys.argv[1]
    in_pss = False
    total = 0
    for line in sys.stdin:
        s = line.strip()
        if s.startswith("Total PSS by process:"):
            in_pss = True
            continue
        if in_pss and s.startswith("Total "):
            break  # next section header (e.g. "Total PSS by OOM adjustment:") ends the list
        if not in_pss:
            continue
        m = re.match(r"([\d,]+)K:\s*(\S+)", s)
        if not m:
            continue
        kb, name = int(m.group(1).replace(",", "")), m.group(2)
        if name == pkg or (":sandboxed_process" in name and "webview" in name.lower()):
            total += kb
    print(f"TOTAL PSS: {total}")


if __name__ == "__main__":
    main()
