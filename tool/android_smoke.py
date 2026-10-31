#!/usr/bin/env python3
"""Drive the installed release APK into the video player and prove it opened.

This runs on the emulator host, next to `adb`, inside the android-smoke
workflow. It uses the UI hierarchy rather than hard-coded coordinates, so a
change to the shelf layout does not silently turn the gate into a no-op.
"""

from __future__ import annotations

import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

PACKAGE = "app.best.best_app"
ACTIVITY = f"{PACKAGE}/.MainActivity"


def adb(*args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["adb", *args],
        check=check,
        capture_output=True,
        text=True,
        timeout=90,
    )
    return result.stdout


def dump() -> ET.Element:
    last = ""
    for _ in range(4):
        adb("shell", "uiautomator", "dump", "/sdcard/window.xml", check=False)
        xml = adb("shell", "cat", "/sdcard/window.xml", check=False)
        if xml.lstrip().startswith("<?xml"):
            try:
                return ET.fromstring(xml)
            except ET.ParseError as error:
                last = str(error)
        else:
            last = xml[:200]
        time.sleep(1)
    raise SystemExit(f"uiautomator returned no hierarchy: {last}")


def nodes(root: ET.Element):
    return list(root.iter("node"))


def find(root: ET.Element, wanted: str) -> ET.Element | None:
    for node in nodes(root):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        if text == wanted or desc == wanted:
            return node
    return None


def find_contains(root: ET.Element, wanted: str) -> ET.Element | None:
    for node in nodes(root):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        if wanted in text or wanted in desc:
            return node
    return None


def center(node: ET.Element) -> tuple[int, int]:
    numbers = [int(value) for value in re.findall(r"\d+", node.get("bounds", ""))]
    if len(numbers) != 4:
        raise SystemExit(f"node has no usable bounds: {node.attrib}")
    x1, y1, x2, y2 = numbers
    return (x1 + x2) // 2, (y1 + y2) // 2


def tap(node: ET.Element, wait: float = 2.0) -> None:
    x, y = center(node)
    adb("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def swipe_up() -> None:
    size = adb("shell", "wm", "size")
    match = re.search(r"(\d+)x(\d+)", size)
    width, height = (320, 640) if not match else map(int, match.groups())
    x = width // 2
    adb(
        "shell",
        "input",
        "swipe",
        str(x),
        str(int(height * 0.72)),
        str(x),
        str(int(height * 0.32)),
        "350",
    )
    time.sleep(1.2)


def wait_for(
    wanted: str,
    *,
    timeout: float = 25,
    scrolls: int = 0,
    contains: bool = False,
) -> ET.Element:
    deadline = time.time() + timeout
    attempts = 0
    while time.time() < deadline:
        root = dump()
        node = find_contains(root, wanted) if contains else find(root, wanted)
        if node is not None:
            return node
        if attempts < scrolls:
            swipe_up()
            attempts += 1
        else:
            time.sleep(1.5)
    raise SystemExit(f"could not find {wanted!r} after {timeout:.0f}s")


def fail_if_playback_error() -> None:
    log = adb("logcat", "-d", "-v", "brief", check=False)
    fatal = [
        line
        for line in log.splitlines()
        if "FATAL EXCEPTION" in line
        or "ExoPlaybackException" in line
        or "PlaybackException" in line
        or ("AndroidRuntime" in line and "FATAL" in line)
    ]
    if fatal:
        print("\n".join(fatal[-40:]))
        raise SystemExit("a fatal playback error was logged")


def main() -> int:
    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(14)

    tap(wait_for("Browse", timeout=30), wait=3)
    tap(wait_for("Neon Seoul", timeout=30, scrolls=3), wait=5)

    # A rerun against an emulator with saved data offers "Continue watching".
    cta = find(dump(), "Watch now")
    if cta is None:
        cta = find(dump(), "Continue watching")
    if cta is None:
        cta = wait_for("Watch now", timeout=30, scrolls=4)
    tap(cta, wait=18)

    # Controls auto-hide after three seconds. Each attempt taps to reveal them,
    # dumps immediately, then waits long enough for a failed attempt to hide
    # them again before the next tap.
    size = adb("shell", "wm", "size")
    match = re.search(r"(\d+)x(\d+)", size)
    width, height = (320, 640) if not match else map(int, match.groups())
    expected = ["Neon Seoul", "Episode 1", "Sample video"]
    missing = expected
    root = dump()
    for _ in range(3):
        adb("shell", "input", "tap", str(width // 2), str(height // 2))
        time.sleep(0.5)
        root = dump()
        missing = [
            text
            for text in expected
            if find(root, text) is None and find_contains(root, text) is None
        ]
        if not missing:
            break
        time.sleep(4)

    if missing:
        print("visible text:")
        for node in nodes(root):
            text = (node.get("text") or "").strip()
            if text:
                print(f"  {text!r}")
        raise SystemExit(f"the player did not render: {missing}")

    fail_if_playback_error()
    print("playback smoke: the player opened and no fatal playback error was logged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
