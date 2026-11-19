#!/usr/bin/env python3
"""Compose record-comparison.sh's two recordings into one side-by-side video with the measured numbers on it.

    compose-comparison.py [--dir out/comparison] [--out out/comparison/comparison.mp4] [--title TEXT]

Reads <dir>/{migo,webview}.{mp4,csv} and meta.txt. Each sample in the CSVs (second, fps, pss_kb) becomes a caption under
its arm, shown from that second until the next sample, so the numbers on screen are the harness's own, at the time
they were taken -- nothing is smoothed or invented between samples. A footer says how they were measured, because a
number without its method is the kind of claim this repository exists not to make. Needs ffmpeg with libass.
"""
import argparse
import csv
import pathlib
import subprocess
import sys

ARMS = (("migo", "Migo"), ("webview", "System WebView / 系统 WebView"))


def ass_time(seconds: float) -> str:
    h, rest = divmod(max(0.0, seconds), 3600)
    m, s = divmod(rest, 60)
    return f"{int(h)}:{int(m):02d}:{s:05.2f}"


def subtitles(rows, label, length, width, height, font):
    head = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {width}
PlayResY: {height}

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Label,{font},{height // 26},&H00FFFFFF,&H00000000,&H90000000,1,0,0,0,100,100,0,0,3,2,0,8,10,10,{height // 40},1
Style: Numbers,{font},{height // 22},&H0066D9FF,&H00000000,&H90000000,1,0,0,0,100,100,0,0,3,2,0,2,10,10,{height // 30},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    events = [f"Dialogue: 0,{ass_time(0)},{ass_time(length)},Label,,0,0,0,,{label}"]
    for i, row in enumerate(rows):
        start = float(row["second"])
        end = float(rows[i + 1]["second"]) if i + 1 < len(rows) else length
        mb = int(row["pss_kb"] or 0) / 1024
        events.append(f"Dialogue: 0,{ass_time(start)},{ass_time(end)},Numbers,,0,0,0,,{row['fps']} fps   {mb:.0f} MB")
    return head + "\n".join(events) + "\n"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parent.parent / "out" / "comparison")
    parser.add_argument("--out", type=pathlib.Path, default=None)
    parser.add_argument("--title", default="")
    parser.add_argument("--font", default="Microsoft YaHei" if sys.platform == "win32" else "PingFang SC",
                        help="a font with CJK glyphs for the captions")
    args = parser.parse_args()
    d = args.dir
    out = args.out or d / "comparison.mp4"
    meta = dict(line.split("=", 1) for line in (d / "meta.txt").read_text().split() if "=" in line)
    height = 1280
    inputs, filters, labels = [], [], []
    for i, (arm, label) in enumerate(ARMS):
        rows = list(csv.DictReader(open(d / f"{arm}.csv", encoding="utf-8")))
        if not rows:
            sys.exit(f"{arm}.csv has no samples")
        length = float(rows[-1]["second"]) + 1
        probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                                "-of", "csv=p=0", f"{arm}.mp4"], capture_output=True, text=True, check=True, cwd=d)
        w, h = (int(v) for v in probe.stdout.strip().split(","))
        width = round(w * height / h / 2) * 2
        (d / f"{arm}.ass").write_text(subtitles(rows, label, length, width, height, args.font), encoding="utf-8")
        # Run from the directory and name files relatively: a drive letter's colon would need escaping in the graph.
        inputs += ["-i", f"{arm}.mp4"]
        filters.append(f"[{i}:v]scale={width}:{height},ass={arm}.ass[v{i}]")
        labels.append(f"[v{i}]")
    method = (f"{meta.get('device_model', '')} · the same game code on both · recorded one after the other",
              "fps = frames presented (SurfaceFlinger)  ·  memory = PSS, including the WebView renderer process")
    title = args.title or f"{meta.get('game_asset', '')}"
    escape = lambda text: text.replace("\\", "\\\\").replace(":", "\\:").replace("'", "")   # drawtext's own quoting
    first, second, title_text = escape(method[0]), escape(method[1]), escape(title)
    footer = (f"drawtext=text='{first}':fontcolor=white@0.85:fontsize=16:x=(w-text_w)/2:y=h-52,"
              f"drawtext=text='{second}':fontcolor=white@0.85:fontsize=16:x=(w-text_w)/2:y=h-28,"
              f"drawtext=text='{title_text}':fontcolor=white:fontsize=28:x=(w-text_w)/2:y=12")
    graph = ";".join(filters) + f";{''.join(labels)}hstack=inputs={len(labels)},pad=iw:ih+110:0:48:black,{footer}[v]"
    cmd = ["ffmpeg", "-y", *inputs, "-filter_complex", graph, "-map", "[v]", "-c:v", "libx264", "-crf", "20",
           "-pix_fmt", "yuv420p", "-shortest", str(out.resolve())]
    result = subprocess.run(cmd, capture_output=True, text=True, cwd=d)
    if result.returncode != 0:
        sys.exit(result.stderr[-2000:])
    print(f"-> {out}")


if __name__ == "__main__":
    main()
