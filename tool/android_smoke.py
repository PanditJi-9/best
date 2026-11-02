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


def find_prefix(root: ET.Element, wanted: str) -> ET.Element | None:
    """The first label that starts with `wanted`.

    Flutter's navigation destinations append `Tab N of M`, so the exact
    label is not stable. Prefix matching is still precise: a paragraph
    that merely mentions "Browse" does not start with it.
    """
    for node in nodes(root):
        text = (node.get("text") or "").strip()
        desc = (node.get("content-desc") or "").strip()
        if text.startswith(wanted) or desc.startswith(wanted):
            return node
    return None


def find_any(root: ET.Element, wanted: str) -> ET.Element | None:
    """Exact first, then a label prefix, then a substring.

    The prefix step matters: the empty shelf contains the sentence "Add a work
    from Browse, or open the built-in guide...". A plain substring search found
    that paragraph before the Browse tab and tapped the middle of the screen.
    """
    for finder in (find, find_prefix, find_contains):
        node = finder(root, wanted)
        if node is not None:
            return node
    return None


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


def dismiss_anr() -> None:
    """Close a "… isn't responding" dialog.

    The emulator's launcher ANRs under load and its dialog steals the screen,
    which makes every later tap land on the dialog instead of the app.
    """
    for _ in range(3):
        node = find_any(dump(), "Wait")
        if node is None:
            return
        tap(node, wait=1.5)


def select_source(wanted: str) -> None:
    """Find a source even when several viewports of pills precede it."""
    root = dump()
    row = find(root, wanted)
    if row is not None:
        tap(row, wait=4)
        return
    row = find_any(root, "All sources")
    if row is None:
        row = find_any(root, "MangaDex")
    if row is None:
        raise SystemExit("the source chip row did not render")
    _, y = center(row)
    match = re.search(r"(\d+)x(\d+)", adb("shell", "wm", "size"))
    width = 320 if not match else int(match.group(1))
    for _ in range(14):
        node = find(root, wanted)
        if node is not None:
            tap(node, wait=4)
            return
        adb("shell", "input", "swipe", str(width - 25), str(y), "20", str(y), "300")
        time.sleep(1.2)
        root = dump()
    debug_texts(root)
    raise SystemExit(f"could not reach source {wanted!r}")


def select_guide() -> None:
    select_source("Best Guide")


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
    dismiss_anr()

    # The workflow also screenshots the home screen, but it can catch an
    # emulator dialog. Take it again once the app is actually on screen.
    wait_for("Search all sources", timeout=40)
    dismiss_anr()
    screenshot("screenshot.png")

    size = adb("shell", "wm", "size")
    match = re.search(r"(\d+)x(\d+)", size)
    width, height = (320, 640) if not match else map(int, match.groups())

    # The bottom bar's accessibility label is not stable across Flutter
    # versions, so fall back to its fixed position on this emulator.
    browse = find_prefix(dump(), "Browse")
    if browse is not None:
        tap(browse, wait=3)
    else:
        adb("shell", "input", "tap", str(width // 2), str(height * 19 // 20))
        time.sleep(3)

    select_guide()
    tap(wait_for("Neon Seoul", timeout=30, scrolls=3), wait=5)

    # A rerun against an emulator with saved data offers "Continue watching".
    root = dump()
    cta = find_any(root, "Watch now")
    if cta is None:
        cta = find_any(root, "Continue watching")
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
