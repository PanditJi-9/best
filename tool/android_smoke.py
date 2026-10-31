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


def find_any(root: ET.Element, wanted: str) -> ET.Element | None:
    """Exact first, then substring.

    Flutter's navigation destinations expose a label together with a position
    hint ("Browse, tab 2 of 4") on some platform versions, so an exact match is
    not something the harness should depend on.
    """
    return find(root, wanted) or find_contains(root, wanted)


def debug_texts(root: ET.Element) -> None:
    print("visible semantics:")
    for node in nodes(root):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        if text or desc:
            print(f"  text={text!r} desc={desc!r} bounds={node.get('bounds')}")


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
        node = find_contains(root, wanted) if contains else find_any(root, wanted)
        if node is not None:
            return node
        if attempts < scrolls:
            swipe_up()
            attempts += 1
        else:
            time.sleep(1.5)
    debug_texts(root)
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


def screenshot(path: str) -> None:
    result = subprocess.run(
        ["adb", "exec-out", "screencap", "-p"],
        capture_output=True,
        timeout=60,
    )
    if result.returncode == 0 and result.stdout.startswith(b"\x89PNG"):
        with open(path, "wb") as handle:
            handle.write(result.stdout)
        print(f"saved {path}")


def main() -> int:
    try:
        return _run()
    finally:
        screenshot("playback.png")


def _run() -> int:
    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(14)

    size = adb("shell", "wm", "size")
    match = re.search(r"(\d+)x(\d+)", size)
    width, height = (320, 640) if not match else map(int, match.groups())

    # The bottom bar's accessibility label is not stable across Flutter
    # versions, so fall back to its fixed position on this emulator.
    browse = find_any(dump(), "Browse")
    if browse is not None:
        tap(browse, wait=3)
    else:
        adb("shell", "input", "tap", str(width * 3 // 8), str(height * 19 // 20))
        time.sleep(3)

    tap(wait_for("Neon Seoul", timeout=30, scrolls=3), wait=5)

    # A rerun against an emulator with saved data offers "Continue watching".
    cta = find_any(dump(), "Watch now") or find_any(dump(), "Continue watching")
    if cta is None:
        cta = wait_for("Watch now", timeout=30, scrolls=4)
    tap(cta, wait=18)

    # Controls auto-hide after three seconds while the video plays. Tap once to
    # reveal them, then tap the centre again: when the controls are visible the
    # big play/pause button sits exactly there, so the second tap pauses the
    # video and the overlay stops hiding. That makes the dump deterministic
    # instead of racing a three-second timer.
    expected = ["Neon Seoul", "Episode 1", "Sample video"]
    missing = expected
    root = dump()
    for _ in range(4):
        adb("shell", "input", "tap", str(width // 2), str(height // 2))
        time.sleep(0.4)
        adb("shell", "input", "tap", str(width // 2), str(height // 2))
        time.sleep(0.6)
        root = dump()
        missing = [text for text in expected if find_any(root, text) is None]
        if not missing:
            break
        time.sleep(3)

    if missing:
        debug_texts(root)
        raise SystemExit(f"the player did not render: {missing}")

    fail_if_playback_error()
    print("playback smoke: the player opened and no fatal playback error was logged")
    return 0


if __name__ == "__main__":
    sys.exit(main())
