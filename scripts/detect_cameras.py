#!/usr/bin/env python3
"""Detect MJPEG-capable USB capture devices and their best supported mode.

Each camera is identified by its /dev/v4l/by-path/ entry, which is tied to the
physical USB port it's plugged into and survives reboots (unlike /dev/videoN,
which can reorder).

For each camera we also probe the resolutions/frame rates it actually supports
and pick a sensible MJPEG mode, so the installer never configures a mode the
camera can't deliver (which would stop uStreamer from starting).

Usage:
    detect_cameras.py             # human-readable table
    detect_cameras.py --paths-only   # one by-path device per line
    detect_cameras.py --config       # "<device>\\t<WxH>\\t<fps>" per camera
"""

import argparse
import glob
import os
import re
import subprocess
import sys

# Cap the auto-selected resolution so an old Pi isn't asked to shovel more than
# it (or a shared USB 2.0 bus) can handle. Users can raise it in the conf later.
MAX_W, MAX_H = 1280, 720
MAX_FPS = 30
MIN_SMOOTH_FPS = 15  # prefer a slightly smaller frame at >= this many fps


def run(cmd):
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=10
        ).stdout
    except Exception:
        return ""


def model_name(device):
    for line in run(["v4l2-ctl", "-d", device, "--info"]).splitlines():
        line = line.strip()
        if line.startswith("Card type"):
            return line.split(":", 1)[1].strip()
    return "Unknown camera"


def mjpeg_modes(device):
    """Parse `--list-formats-ext` and return {(w,h): max_fps} for the MJPG format."""
    text = run(["v4l2-ctl", "-d", device, "--list-formats-ext"])
    modes = {}
    in_mjpeg = False
    cur = None
    for line in text.splitlines():
        s = line.strip()
        fmt = re.search(r"'(\w+)'", s)
        if s.startswith("[") and fmt:
            in_mjpeg = fmt.group(1) in ("MJPG",)
            continue
        if not in_mjpeg:
            continue
        size = re.search(r"Discrete\s+(\d+)x(\d+)", s)
        if size:
            cur = (int(size.group(1)), int(size.group(2)))
            modes.setdefault(cur, 0.0)
            continue
        fps = re.search(r"\(([\d.]+)\s*fps\)", s)
        if fps and cur:
            modes[cur] = max(modes[cur], float(fps.group(1)))
    return modes


def pick_mode(modes):
    """Choose a resolution/fps: largest frame (<= cap) that runs smoothly."""
    if not modes:
        return f"{MAX_W}x{MAX_H}", MAX_FPS  # fall back to a common default
    capped = {wh: f for wh, f in modes.items() if wh[0] <= MAX_W and wh[1] <= MAX_H}
    pool = capped or modes  # if every mode exceeds the cap, consider them all
    smooth = {wh: f for wh, f in pool.items() if f >= MIN_SMOOTH_FPS}
    chosen_pool = smooth or pool
    (w, h) = max(chosen_pool, key=lambda wh: wh[0] * wh[1])
    fps = int(min(chosen_pool[(w, h)] or MAX_FPS, MAX_FPS))
    return f"{w}x{h}", fps


def detect():
    """Return [(by_path, real_device, model, resolution, fps)] for capture nodes."""
    found = []
    seen_real = set()
    # index0 of the capture interface is the actual video node; sorting by the
    # by-path string gives a stable, repeatable cam1/cam2 ordering.
    for by_path in sorted(glob.glob("/dev/v4l/by-path/*-video-index0")):
        real = os.path.realpath(by_path)
        if real in seen_real:
            continue
        modes = mjpeg_modes(by_path)
        if not modes:
            continue  # no MJPEG capture here (also filters out metadata nodes)
        seen_real.add(real)
        resolution, fps = pick_mode(modes)
        found.append((by_path, real, model_name(by_path), resolution, fps))
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--paths-only", action="store_true",
                   help="print only the by-path device, one per line")
    g.add_argument("--config", action="store_true",
                   help="print '<device>\\t<WxH>\\t<fps>' per camera (for the installer)")
    args = ap.parse_args()

    cams = detect()

    if args.paths_only:
        for by_path, *_ in cams:
            print(by_path)
        return 0

    if args.config:
        for by_path, _real, _model, resolution, fps in cams:
            print(f"{by_path}\t{resolution}\t{fps}")
        return 0

    if not cams:
        print("No MJPEG-capable capture cameras found.", file=sys.stderr)
        print("Check connections and that 'v4l-utils' is installed.", file=sys.stderr)
        return 1

    print(f"Detected {len(cams)} camera(s):\n")
    for i, (by_path, real, model, resolution, fps) in enumerate(cams, start=1):
        print(f"  cam{i}: {model}")
        print(f"        device:  {real}")
        print(f"        by-path: {by_path}")
        print(f"        mode:    {resolution} @ {fps} fps (auto-selected MJPEG)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
