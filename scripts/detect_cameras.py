#!/usr/bin/env python3
"""Detect MJPEG-capable USB capture devices and report stable by-path devices.

Each camera is identified by its /dev/v4l/by-path/ entry, which is tied to the
physical USB port it's plugged into and survives reboots (unlike /dev/videoN,
which can reorder).

Usage:
    detect_cameras.py            # human-readable table
    detect_cameras.py --paths-only   # one device path per line (for scripts)
"""

import argparse
import glob
import os
import subprocess
import sys


def run(cmd):
    try:
        return subprocess.run(
            cmd, capture_output=True, text=True, timeout=10
        ).stdout
    except Exception:
        return ""


def supports_mjpeg(device):
    """True if the v4l2 node can capture MJPEG (also filters out metadata nodes)."""
    fmts = run(["v4l2-ctl", "-d", device, "--list-formats"])
    return "MJPG" in fmts or "Motion-JPEG" in fmts


def model_name(device):
    info = run(["v4l2-ctl", "-d", device, "--info"])
    for line in info.splitlines():
        line = line.strip()
        if line.startswith("Card type"):
            return line.split(":", 1)[1].strip()
    return "Unknown camera"


def detect():
    """Return a sorted list of (by_path, real_device, model) for capture nodes."""
    found = []
    seen_real = set()
    # index0 of the capture interface is the actual video node; sorting by the
    # by-path string gives a stable, repeatable cam1/cam2 ordering.
    for by_path in sorted(glob.glob("/dev/v4l/by-path/*-video-index0")):
        real = os.path.realpath(by_path)
        if real in seen_real:
            continue
        if not supports_mjpeg(by_path):
            continue
        seen_real.add(real)
        found.append((by_path, real, model_name(by_path)))
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--paths-only",
        action="store_true",
        help="print only the by-path device, one per line",
    )
    args = ap.parse_args()

    cams = detect()

    if args.paths_only:
        for by_path, _real, _model in cams:
            print(by_path)
        return 0

    if not cams:
        print("No MJPEG-capable capture cameras found.", file=sys.stderr)
        print("Check connections and that 'v4l-utils' is installed.", file=sys.stderr)
        return 1

    print(f"Detected {len(cams)} camera(s):\n")
    for i, (by_path, real, model) in enumerate(cams, start=1):
        print(f"  cam{i}: {model}")
        print(f"        device:  {real}")
        print(f"        by-path: {by_path}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
