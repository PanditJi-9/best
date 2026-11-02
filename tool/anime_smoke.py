#!/usr/bin/env python3
"""Open real extension catalogues, episodes and video on the Actions emulator.

All starter bundles must load (extension_probe.py). This gate additionally
requires at least one real anime to play and advance; a sample film, empty
catalogue, decoded URL or stationary player alone cannot pass it.
"""

from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

from android_smoke import (
    ACTIVITY, PACKAGE, adb, debug_texts, dismiss_anr, dump, find_any, nodes,
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


def check_source(name: str, *, play: bool) -> dict:
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
    report = {"source": name, "title": title, "catalogue": True, "episodes": True, "playback": False}
    if not play:
        return report
    tap(cta, wait=10)

    match = re.search(r"(\d+)x(\d+)", adb("shell", "wm", "size"))
    width, height = map(int, match.groups()) if match else (320, 640)
    deadline = time.monotonic() + 100
    initial = None
    while time.monotonic() < deadline:
        root = dump()
        error = error_on_screen(root)
        if error:
            raise RuntimeError(f"{name} player: {error}")
        if find_any(root, "Sample video") is not None:
            raise RuntimeError("sample playback is not anime verification")
        clock = playback_clock(root)
        if clock is not None and clock[1] > 0:
            if initial is None:
                initial = clock[0]
            elif clock[0] >= initial + 3:
                report.update(playback=True, position=clock[0], duration=clock[1])
                screenshot(f"anime-{name}-playback.png")
                print(f"anime playback: {name} / {title} advanced from {initial}s to {clock[0]}s")
                return report
        # Reveal controls away from the centre play/pause button. Never seek:
        # the clock must advance because the actual stream is playing.
        if find_any(root, "Playback speed") is None:
            adb("shell", "input", "tap", str(width // 2), str(height // 3))
        time.sleep(2)
    debug_texts(root)
    raise RuntimeError(f"{name} video did not advance")


def main() -> int:
    reports = []
    played = False
    for name in SOURCES:
        try:
            report = check_source(name, play=not played)
            played = played or report["playback"]
            reports.append(report)
        except (RuntimeError, SystemExit) as error:
            print(f"anime smoke: {name}: {error}")
            screenshot(f"anime-{name}-failure.png")
            reports.append({"source": name, "error": str(error)})
        finally:
            Path("anime-results.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2))
    print(json.dumps(reports, ensure_ascii=False, indent=2))
    # A dead site must not hide the fact no extension stream ever played. Site
    # failures remain in the report, even if another source supplies the gate.
    return 0 if played else 1


if __name__ == "__main__":
    sys.exit(main())
