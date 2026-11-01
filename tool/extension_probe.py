#!/usr/bin/env python3
"""Report what the source list actually contains after a first launch.

This is a diagnostic, not a gate: it opens the app, waits for the starter
extension set to install itself, walks to Browse, and prints every label it can
see. The workflow uploads the output so a failed extension load is visible
without a device.

It exits 0 even when nothing loads — `android_smoke.py` is the gate; this file
answers "did the extensions work?".
"""

from __future__ import annotations

import subprocess
import sys
import re
import time
import xml.etree.ElementTree as ET

PACKAGE = "app.best.best_app"
ACTIVITY = f"{PACKAGE}/.MainActivity"

# Names the starter set is expected to produce. Kept loose on purpose: a source
# label is the extension's own string and may change case or add a suffix.
EXPECTED = ("MangaDex", "MangaFire", "Weeb", "MangaKatana", "3asq")


def adb(*args: str, check: bool = False) -> str:
    try:
        result = subprocess.run(
            ["adb", *args], check=check, capture_output=True, text=True, timeout=90
        )
        return result.stdout
    except subprocess.TimeoutExpired:
        return ""


def labels() -> list[str]:
    adb("shell", "uiautomator", "dump", "/sdcard/probe.xml")
    xml = adb("shell", "cat", "/sdcard/probe.xml")
    if not xml.lstrip().startswith("<?xml"):
        return []
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return []
    found = []
    for node in root.iter("node"):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        for value in (text, desc):
            if value:
                found.append(value)
    return found


def tap(label_prefix: str) -> bool:
    for _ in range(6):
        seen = labels()
        if any(value.startswith(label_prefix) for value in seen):
            # uiautomator cannot tap by label, so ask the app to do it through a
            # tap on the node's bounds.
            adb("shell", "uiautomator", "dump", "/sdcard/probe.xml")
            xml = adb("shell", "cat", "/sdcard/probe.xml")
            try:
                root = ET.fromstring(xml)
            except ET.ParseError:
                return False
            for node in root.iter("node"):
                text = (node.get("text") or "").strip()
                desc = (node.get("content-desc") or "").strip()
                if text.startswith(label_prefix) or desc.startswith(label_prefix):
                    bounds = node.get("bounds") or ""
                    if bounds:
                        try:
                            left, top, right, bottom = (
                                int(part)
                                for part in bounds.replace("][", ",").strip("[]").split(",")
                            )
                            adb(
                                "shell",
                                "input",
                                "tap",
                                str((left + right) // 2),
                                str((top + bottom) // 2),
                            )
                            return True
                        except ValueError:
                            continue
        time.sleep(2)
    return False


def horizontal_swipe() -> None:
    """Pull the source chip row left, so chips past the fold get laid out."""
    size = adb("shell", "wm", "size")
    match = re.search(r"(\d+)x(\d+)", size)
    width, height = (320, 640) if not match else map(int, match.groups())
    y = int(height * 0.22)
    adb("shell", "input", "swipe", str(width - 30), str(y), "20", str(y), "300")
    time.sleep(1.2)


def main() -> int:
    adb("shell", "am", "force-stop", PACKAGE)
    adb("shell", "am", "start", "-n", ACTIVITY)
    # First launch: the starter set downloads five APKs before Browse has
    # anything to say, so give the download room and then keep checking.
    time.sleep(30)
    tap("Browse")
    time.sleep(8)

    seen: list[str] = []
    for attempt in range(18):
        seen.extend(labels())
        if attempt in (5, 11):
            # Still empty after a minute: the list may have rendered before the
            # catalog arrived, so visit Browse again.
            tap("Browse")
        time.sleep(6)

    # Chips past the right edge are not in the hierarchy until they are scrolled
    # into view, so walk the row before deciding a source is missing.
    for _ in range(4):
        horizontal_swipe()
        seen.extend(labels())

    unique = sorted({value for value in seen if value})
    matched = [name for name in EXPECTED if any(name.lower() in value.lower() for value in unique)]
    ready = next(
        (value for value in unique if "source" in value.lower() and "ready" in value.lower()),
        "",
    )

    print("--- visible labels ---")
    for value in unique:
        print(value)
    print("--- sources ready ---")
    print(ready or "unknown")
    print("--- expected sources found ---")
    print(", ".join(matched) if matched else "none")
    print(f"matched {len(matched)} of {len(EXPECTED)}")

    try:
        with open("sources.txt", "w", encoding="utf-8") as handle:
            handle.write("\n".join(unique))
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
