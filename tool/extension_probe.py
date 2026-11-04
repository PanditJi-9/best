#!/usr/bin/env python3
"""Activate regression selections through the full directory, then gate loads.

A built-in MangaDex chip is not proof its extension loaded. The native host
logs each registered source with its owning package. These nine choices belong
to the test only; the application must not silently install them on startup.
"""

from __future__ import annotations

import os
import re
import sys
import time
from pathlib import Path

from android_smoke import (
    ACTIVITY, PACKAGE, adb, debug_texts, dismiss_anr, dump, find_any, nodes,
    open_sources, swipe_up, tap, wait_for,
)

MANGA_PACKAGES = (
    "eu.kanade.tachiyomi.extension.all.mangadex",
    "eu.kanade.tachiyomi.extension.all.mangafire",
    "eu.kanade.tachiyomi.extension.en.weebcentral",
    "eu.kanade.tachiyomi.extension.en.mangakatana",
    "eu.kanade.tachiyomi.extension.ar.manga3asq",
)
ANIME_PACKAGES = (
    "eu.kanade.tachiyomi.animeextension.all.anizone",
    "eu.kanade.tachiyomi.animeextension.en.animepahe",
    "eu.kanade.tachiyomi.animeextension.en.kotokai",
    "eu.kanade.tachiyomi.animeextension.all.animexin",
)
# Targeted runs add packages through the workflow input; the default nine stay
# the regression selection.
EXPECTED = MANGA_PACKAGES + ANIME_PACKAGES + tuple(
    package.strip()
    for package in os.environ.get("EXTRA_PACKAGES", "").split(",")
    if package.strip()
)


def activate_from_directory(package: str) -> None:
    """Search by exact package identity, never pick an ambiguous site name."""
    root = dump()
    field = next((n for n in nodes(root) if n.get("class") == "android.widget.EditText"), None)
    if field is None:
        debug_texts(root)
        raise SystemExit("directory search field did not render")
    tap(field, wait=0.3)
    adb("shell", "input", "text", package)
    time.sleep(1)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")  # Hide keyboard, not the page.
    root = dump()
    button = find_any(root, "Activate")
    if button is not None:
        tap(button, wait=1)
        root = dump()
        trust = find_any(root, "Trust & activate")
        if trust is not None:
            tap(trust, wait=1)
    deadline = time.monotonic() + 100
    while time.monotonic() < deadline:
        if package in loaded_packages(adb("logcat", "-d", "-v", "brief", check=False)):
            break
        time.sleep(2)
    else:
        debug_texts(dump())
        raise SystemExit(f"directory activation did not load {package}")
    tap(wait_for("Cancel"), wait=0.4)  # Search field's accessible clear button.


def loaded_packages(log: str) -> set[str]:
    return set(re.findall(r"BestExtensions.*\bloaded .+ from ([\w.]+)", log))


def main() -> int:
    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(8)
    dismiss_anr()
    # Your sources is where a reader's own sources live; its header button
    # opens the full directory.
    open_sources()
    before = loaded_packages(adb("logcat", "-d", "-v", "brief", check=False))
    if before:
        raise SystemExit(f"a fresh install activated extensions without a choice: {before}")
    tap(wait_for("Extension directory", timeout=40), wait=4)
    wait_for("extensions ·", timeout=70, contains=True)
    root = dump()
    counts = next((n for n in nodes(root) if "extensions ·" in
                   ((n.get("text") or "") + (n.get("content-desc") or ""))), None)
    text = (counts.get("text") or counts.get("content-desc") or "") if counts is not None else ""
    match = re.search(r"(\d+) extensions", text)
    if not match or int(match.group(1)) < 1000:
        raise SystemExit(f"full directory did not expose 1000+ upstream bundles: {text}")
    Path("directory.xml").write_text(ET_to_string(root), encoding="utf-8")
    adb("shell", "screencap", "-p", "/sdcard/directory.png")
    adb("pull", "/sdcard/directory.png", "directory.png")
    for package in EXPECTED:
        activate_from_directory(package)
    adb("shell", "input", "keyevent", "KEYCODE_BACK")

    # Require actual loads, independent of deliberate manga language filtering.
    deadline = time.monotonic() + 150
    while True:
        loaded = loaded_packages(adb("logcat", "-d", "-v", "brief", check=False))
        missing = set(EXPECTED) - loaded
        if not missing or time.monotonic() >= deadline:
            break
        time.sleep(5)

    # Back on the Manga tab, every activated source is a row in a vertical
    # list; collect the visible labels for the artifact.
    root = dump()
    seen: set[str] = set()
    for _ in range(10):
        for node in nodes(root):
            for field in ("text", "content-desc"):
                value = (node.get(field) or "").strip()
                if value:
                    seen.add(value)
        swipe_up()
        root = dump()

    with open("sources.txt", "w", encoding="utf-8") as handle:
        handle.write("\n".join(sorted(seen)))
        handle.write("\n\nLoaded test selections:\n" + "\n".join(sorted(set(EXPECTED) & loaded)))
        handle.write("\n\nMissing test selections:\n" + "\n".join(sorted(missing)))
    print(f"extension gate: {len(set(EXPECTED) & loaded)} / {len(EXPECTED)} bundles loaded")
    for pkg in sorted(missing):
        print(f"MISSING: {pkg}")
    return 1 if missing else 0


def ET_to_string(root) -> str:
    import xml.etree.ElementTree as ET
    return ET.tostring(root, encoding="unicode")


if __name__ == "__main__":
    sys.exit(main())
