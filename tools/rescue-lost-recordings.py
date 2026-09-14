#!/usr/bin/env python3
"""Rescue lost recordings — pull the orphaned `rec_tmp_*.m4a` files off the iPhone.

A recording is persisted NOWHERE until `stop()` (LiveRecordingService.swift:433 →
RecordView.swift:548): the audio goes to `Documents/recordings/rec_tmp_<uuid>.m4a`
and only becomes a memo when the user stops it. So every time the app dies
mid-recording — a call suspends it and iOS jetsams it, a crash, a swipe-kill —
the take is lost and that file is orphaned. Nothing in the app ever looks at
`rec_tmp_*` again, so the orphans are all still there, one per lost recording.

MUST RUN ON THE MAC, with the iPhone plugged in and unlocked. It shells out to
`xcrun devicectl`, so a remote/cloud session cannot do this.

    python3 tools/rescue-lost-recordings.py                 # prod "Skrift"
    python3 tools/rescue-lost-recordings.py --dev           # "Skrift Dev" (+ devlog.txt)
    python3 tools/rescue-lost-recordings.py --device <UDID> # pick the device explicitly
    python3 tools/rescue-lost-recordings.py --scan ./pulled # analyse an already-pulled folder

What it does, in order:
  1. Lists the files ON THE DEVICE first (`devicectl device info files`) — that
     listing carries the real on-device timestamps, which a copy may not preserve.
     The mtime is the forensic bit: it dates the last buffer written, i.e. the
     moment capture stopped for good.
  2. Copies `Documents/recordings` off the device.
  3. Reports every orphan: size, minutes of audio (~1 MB/min at the app's AAC
     settings), and whether the MP4 is FINALIZED.

**Why most orphans won't play.** `AVAudioFile` writes the MP4 index (`moov`) in
`close()`, which only stop/cancel reach (LiveRecordingService.swift:555). A killed
recording leaves the AAC frames sitting in `mdat` with no index, so AVFoundation
and ffmpeg both refuse the file. That is a repairable state, not a lost one — the
audio is there — but it needs a `moov` rebuilt from a reference file recorded by
the same app at the same sample rate. This script tells you WHICH files are in
that state; it does not repair them.
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime

PROD_BUNDLE = "com.skrift.mobile"
DEV_BUNDLE = "com.skrift.mobile.dev"
REMOTE_DIR = "Documents/recordings"

# The app's AAC settings are high-quality mono/stereo at the mic's rate; in
# practice its .m4a files land near this. Only used to turn bytes into a
# human "about N minutes", never into a claim.
BYTES_PER_MINUTE = 1_000_000


# ---------------------------------------------------------------- MP4 boxes

def top_level_boxes(path, limit=64):
    """Yield (type, declared_size, offset) for each top-level MP4 box.

    Handles the two ways a killed writer leaves the file: `size == 0` (this box
    runs to EOF, never patched) and a declared size that overruns the file.
    Both mean nobody ever called close().
    """
    size_on_disk = os.path.getsize(path)
    boxes = []
    with open(path, "rb") as f:
        offset = 0
        while offset < size_on_disk and len(boxes) < limit:
            f.seek(offset)
            header = f.read(8)
            if len(header) < 8:
                break
            size, kind = struct.unpack(">I4s", header)
            try:
                kind = kind.decode("ascii")
            except UnicodeDecodeError:
                break
            if not re.fullmatch(r"[\x20-\x7e]{4}", kind):
                break
            header_len = 8
            if size == 1:                      # 64-bit largesize follows
                largesize = f.read(8)
                if len(largesize) < 8:
                    break
                size = struct.unpack(">Q", largesize)[0]
                header_len = 16
            boxes.append((kind, size, offset))
            if size == 0:                      # runs to EOF
                break
            if size < header_len:              # malformed; stop rather than loop
                break
            offset += size
    return boxes, size_on_disk


def verdict(path):
    """One line on whether this .m4a is playable, plus the boxes behind it."""
    try:
        boxes, size_on_disk = top_level_boxes(path)
    except OSError as exc:
        return f"unreadable ({exc})", []
    kinds = [k for k, _, _ in boxes]
    if not boxes:
        return "not an MP4 (no readable box header) — 0 bytes or a different container", kinds
    has_moov = "moov" in kinds
    unterminated = any(
        (size == 0) or (offset + size > size_on_disk) for _, size, offset in boxes
    )
    if has_moov and not unterminated:
        return "FINALIZED — should play as-is", kinds
    if has_moov:
        return "has moov but a box overruns the file — partially written", kinds
    return "UNFINALIZED — no moov index; audio is in mdat, needs a rebuilt header", kinds


# ---------------------------------------------------------------- devicectl

def run(cmd, check=True):
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def require_devicectl():
    if shutil.which("xcrun") is None:
        sys.exit("xcrun not found. Run this on the Mac, not in a remote session.")


def find_device(explicit):
    """The device's identifier, via devicectl's JSON listing.

    `--device` accepts either the device identifier or the hardware UDID, so
    either is fine to return. The plain-text listing is scraped only as a
    fallback, because its columns have changed across Xcode versions.
    """
    if explicit:
        return explicit
    candidates = []
    with tempfile.NamedTemporaryFile(suffix=".json") as tmp:
        listing = run(["xcrun", "devicectl", "list", "devices",
                       "--json-output", tmp.name], check=False)
        try:
            with open(tmp.name) as handle:
                devices = json.load(handle).get("result", {}).get("devices", [])
        except (OSError, ValueError):
            devices = []
    for device in devices:
        hardware = device.get("hardwareProperties", {})
        if hardware.get("platform") not in (None, "iOS"):
            continue
        ident = device.get("identifier") or hardware.get("udid")
        if ident:
            name = device.get("deviceProperties", {}).get("name", "?")
            candidates.append((ident, name))

    if not candidates:                                   # fallback: scrape the text
        text = listing.stdout or run(["xcrun", "devicectl", "list", "devices"],
                                     check=False).stdout
        for match in re.findall(r"\b([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16})\b", text):
            candidates.append((match, "?"))
        if not candidates:
            print(text)
            sys.exit("No paired device found. Plug the iPhone in, unlock it, trust the Mac.")

    if len({ident for ident, _ in candidates}) > 1:
        for ident, name in candidates:
            print(f"  {ident}  {name}")
        sys.exit("More than one device — pass --device <identifier>.")
    return candidates[0][0]


def list_on_device(udid, bundle):
    """The on-device listing, with the timestamps a copy may not preserve."""
    result = run([
        "xcrun", "devicectl", "device", "info", "files",
        "--device", udid,
        "--domain-type", "appDataContainer",
        "--domain-identifier", bundle,
        "--subdirectory", REMOTE_DIR,
        "--no-recurse",
    ], check=False)
    if result.returncode != 0:
        sys.exit(
            "Could not read the app container.\n"
            f"  bundle: {bundle}\n"
            f"  {result.stderr.strip()}\n"
            "If it says the app is not installed or not debuggable, that build was not "
            "signed for local development and devicectl cannot read its container."
        )
    return result.stdout


def pull(udid, bundle, dest):
    os.makedirs(dest, exist_ok=True)
    result = run([
        "xcrun", "devicectl", "device", "copy", "from",
        "--device", udid,
        "--domain-type", "appDataContainer",
        "--domain-identifier", bundle,
        "--source", REMOTE_DIR,
        "--destination", dest,
    ], check=False)
    if result.returncode != 0:
        sys.exit(f"Copy failed:\n{result.stderr.strip()}")
    return dest


def pull_devlog(udid, bundle, dest):
    """Dev only — Release compiles DevLog to a no-op, so prod has no devlog.txt."""
    result = run([
        "xcrun", "devicectl", "device", "copy", "from",
        "--device", udid,
        "--domain-type", "appDataContainer",
        "--domain-identifier", bundle,
        "--source", "Documents/devlog.txt",
        "--destination", dest,
    ], check=False)
    return result.returncode == 0


# ---------------------------------------------------------------- reporting

def stamp(seconds):
    return datetime.fromtimestamp(seconds).strftime("%Y-%m-%d %H:%M:%S")


def report(folder):
    orphans = []
    for root, _, files in os.walk(folder):
        for name in files:
            if name.startswith("rec_tmp_") and name.endswith(".m4a"):
                orphans.append(os.path.join(root, name))
    orphans.sort(key=os.path.getmtime, reverse=True)

    if not orphans:
        print("\nNo rec_tmp_* files. Either no recording has ever been lost, or they were "
              "pulled from the wrong container (--dev pulls the other one).")
        return orphans

    print(f"\n{len(orphans)} orphaned recording(s), newest first:\n")
    for path in orphans:
        info = os.stat(path)
        born = getattr(info, "st_birthtime", None)
        line, kinds = verdict(path)
        print(f"  {os.path.basename(path)}")
        print(f"    {info.st_size / 1_000_000:.1f} MB  ≈ {info.st_size / BYTES_PER_MINUTE:.0f} min of audio")
        if born:
            print(f"    started  {stamp(born)}")
            print(f"    ended    {stamp(info.st_mtime)}   (capture ran ~{(info.st_mtime - born) / 60:.0f} min)")
        else:
            print(f"    modified {stamp(info.st_mtime)}")
        print(f"    boxes: {' '.join(kinds) or '(none)'}")
        print(f"    {line}\n")

    print("The 'ended' stamp is the forensic one: it dates the last buffer written, so a "
          "recording that ends the moment a call arrived is one the app never came back from.")
    return orphans


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dev", action="store_true", help='pull "Skrift Dev" instead of prod')
    parser.add_argument("--device", help="device UDID (default: the only paired device)")
    parser.add_argument("--dest", default="./rescued-recordings", help="where to copy to")
    parser.add_argument("--scan", metavar="DIR", help="skip the pull, just analyse this folder")
    args = parser.parse_args()

    if args.scan:
        report(args.scan)
        return

    require_devicectl()
    bundle = DEV_BUNDLE if args.dev else PROD_BUNDLE
    udid = find_device(args.device)
    print(f"device {udid}\nbundle {bundle}\n")

    print(f"--- on-device listing of {REMOTE_DIR} (real timestamps) ---")
    print(list_on_device(udid, bundle))

    dest = pull(udid, bundle, args.dest)
    print(f"copied to {dest}")
    if args.dev and pull_devlog(udid, bundle, dest):
        print(f"pulled devlog.txt — grep it for 'interruption BEGAN' and what follows")

    report(dest)


if __name__ == "__main__":
    main()
