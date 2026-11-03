#!/usr/bin/env python3
"""Open real extension catalogues, episodes and video on the Actions emulator.

All selected test bundles must load (extension_probe.py). This gate additionally
requires at least one real anime to play and advance; a sample film, empty
catalogue, decoded URL or stationary player alone cannot pass it.
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path
import xml.etree.ElementTree as ET

from android_smoke import (
    ACTIVITY, PACKAGE, adb, debug_texts, dismiss_anr, dump, find, find_any, nodes,
    screenshot, select_source, swipe_up, tap, wait_for,
)

SOURCES = ("AniZone", "AnimePahe", "AnimeKai", "AnimeXin")


def clock_seconds(text: str) -> int:
    result = 0
    for part in text.split(":"):
        result = result * 60 + int(part)
    return result


def playback_clock(root) -> tuple[int, int] | None:
    for node in nodes(root):
        for field in ("text", "content-desc"):
            match = re.search(r"\b(\d{1,2}:\d{2}(?::\d{2})?) / (\d{1,2}:\d{2}(?::\d{2})?)\b",
                              node.get(field) or "")
            if match:
                return clock_seconds(match.group(1)), clock_seconds(match.group(2))
    return None


def error_on_screen(root) -> str | None:
    for text in ("The source did not answer", "This video could not be played.", "Nothing here yet"):
        if find_any(root, text) is not None:
            debug_texts(root)
            return text
    return None


def paused_player(width: int, height: int):
    """Freeze controls before asking UIAutomator to wait for UI idleness.

    A moving clock keeps changing semantics, and the overlay disappears after
    three seconds. Reveal then pause promptly, just like the guide gate. Only
    touch the backdrop and central play/pause control, never the seek controls.
    An already-visible overlay may need a second attempt.
    """
    for _ in range(4):
        adb("shell", "input", "tap", str(width // 2), str(height // 3))
        time.sleep(0.25)
        adb("shell", "input", "tap", str(width // 2), str(height // 2))
        time.sleep(0.6)
        root = dump()
        if (find(root, "Play") is not None or error_on_screen(root)
                or find_any(root, "Sample video") is not None):
            return root
    return root


def verify_playback(name: str, title: str, report: dict) -> dict:
    match = re.search(r"(\d+)x(\d+)", adb("shell", "wm", "size"))
    width, height = map(int, match.groups()) if match else (320, 640)
    deadline = time.monotonic() + 100
    initial = None
    while time.monotonic() < deadline:
        root = paused_player(width, height)
        error = error_on_screen(root)
        if error:
            raise RuntimeError(f"{name} player: {error}")
        if find_any(root, "Sample video") is not None:
            raise RuntimeError("sample playback is not anime verification")
        button = find(root, "Play")
        clock = playback_clock(root)
        if (button is None or button.get("enabled") != "true"
                or find_any(root, title) is None or clock is None or clock[1] <= 0):
            time.sleep(2)
            continue

        report.setdefault("observations", []).append({"position": clock[0], "duration": clock[1]})
        observation = len(report["observations"])
        Path(f"anime-{name}-playback-{observation}.xml").write_text(ET.tostring(root, encoding="unicode"))
        if initial is None:
            initial = clock
            screenshot(f"anime-{name}-playback-before.png")
        elif clock[1] != initial[1]:
            raise RuntimeError(f"{name} player changed duration during verification")
        elif clock[0] >= initial[0] + 3:
            report.update(playback=True, position_before=initial[0],
                          position=clock[0], duration=clock[1])
            screenshot(f"anime-{name}-playback.png")
            print(f"anime playback: {name} / {title} advanced from {initial[0]}s to {clock[0]}s")
            return report

        # Resume via the actual enabled Play button, wait for real playback, and
        # pause again to read a stable clock. No seeking, screenshots or decoded
        # URLs can substitute for an advancing position on the same real anime.
        tap(button, wait=6)
    debug_texts(root)
    raise RuntimeError(f"{name} video did not advance")


def check_source(name: str, *, play: bool, report: dict | None = None) -> dict:
    if report is None:
        report = {"source": name, "catalogue": False, "episodes": False, "playback": False}
    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(6)
    dismiss_anr()
    tap(wait_for("Browse", timeout=35), wait=3)
    select_source(name)

    deadline = time.monotonic() + 55
    card = None
    while time.monotonic() < deadline:
        root = dump()
        error = error_on_screen(root)
        if error:
            raise RuntimeError(f"{name} catalogue: {error}")
        # MediaCard merges its title and kind into one clickable semantics node.
        # Android may expose it as either a Button or ImageView across versions.
        card = next((node for node in nodes(root)
                     if node.get("clickable") == "true"
                     and "Anime" in (node.get("content-desc") or "").splitlines()
                     and len((node.get("content-desc") or "").splitlines()) > 1), None)
        if card is not None:
            break
        time.sleep(2)
    if card is None:
        debug_texts(root)
        raise RuntimeError(f"{name} returned no visible anime cards")
    title = card.get("content-desc", "").splitlines()[0]
    report.update(title=title, catalogue=True)
    screenshot(f"anime-{name}-catalogue.png")
    tap(card, wait=5)

    # The hero can occupy a whole small screen. Scroll only after the series has
    # loaded, otherwise the swipes disappear into the loading indicator.
    deadline = time.monotonic() + 65
    cta = None
    while time.monotonic() < deadline:
        root = dump()
        error = error_on_screen(root)
        if error:
            raise RuntimeError(f"{name} episodes: {error}")
        cta = find_any(root, "Watch now")
        if cta is None:
            cta = find_any(root, "Continue watching")
        if cta is not None and cta.get("enabled") == "true":
            break
        swipe_up()
    if cta is None or cta.get("enabled") != "true":
        debug_texts(root)
        raise RuntimeError(f"{name} did not offer a playable episode")
    screenshot(f"anime-{name}-episodes.png")
    report["episodes"] = True
    if not play:
        return report
    tap(cta, wait=10)

    return verify_playback(name, title, report)


def main() -> int:
    reports = []
    played = False
    for name in SOURCES:
        report = {"source": name, "catalogue": False, "episodes": False, "playback": False}
        reports.append(report)
        try:
            check_source(name, play=not played, report=report)
            played = played or report["playback"]
        except (RuntimeError, SystemExit) as error:
            print(f"anime smoke: {name}: {error}")
            screenshot(f"anime-{name}-failure.png")
            report["error"] = str(error)
        finally:
            Path("anime-results.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2))
    print(json.dumps(reports, ensure_ascii=False, indent=2))
    # A dead site must not hide the fact no extension stream ever played. Site
    # failures remain in the report, even if another source supplies the gate.
    return 0 if played else 1


if __name__ == "__main__":
    sys.exit(main())
