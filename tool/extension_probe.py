#!/usr/bin/env python3
"""Gate the starter APKs on actual host loads, and capture the Browse labels.

A built-in MangaDex chip is not proof its extension loaded. The native host
logs each registered source with its owning package; require all nine bundles
there, independent of the UI's deliberate manga language filtering.
"""

from __future__ import annotations

import re
import sys
import time

from android_smoke import (
    ACTIVITY, PACKAGE, adb, center, debug_texts, dismiss_anr, dump, find_any,
    nodes, tap, wait_for,
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
EXPECTED = MANGA_PACKAGES + ANIME_PACKAGES


def loaded_packages(log: str) -> set[str]:
    return set(re.findall(r"BestExtensions.*\bloaded .+ from ([\w.]+)", log))


def main() -> int:
    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(8)
    dismiss_anr()
    tap(wait_for("Browse", timeout=40), wait=4)

    # Nine first-run downloads can be slow. Keep a finite budget, and retain the
    # failure rather than passing merely because the two built-in sources exist.
    deadline = time.monotonic() + 150
    while True:
        loaded = loaded_packages(adb("logcat", "-d", "-v", "brief", check=False))
        missing = set(EXPECTED) - loaded
        if not missing or time.monotonic() >= deadline:
            break
        time.sleep(5)

    root = dump()
    row = find_any(root, "All sources")
    if row is None:
        debug_texts(root)
        raise SystemExit("source picker did not render")
    _, y = center(row)
    match = re.search(r"(\d+)x(\d+)", adb("shell", "wm", "size"))
    width = int(match.group(1)) if match else 320
    seen: set[str] = set()
    for _ in range(14):
        for node in nodes(root):
            for field in ("text", "content-desc"):
                value = (node.get(field) or "").strip()
                if value:
                    seen.add(value)
        adb("shell", "input", "swipe", str(width - 25), str(y), "20", str(y), "300")
        time.sleep(0.8)
        root = dump()

    with open("sources.txt", "w", encoding="utf-8") as handle:
        handle.write("\n".join(sorted(seen)))
        handle.write("\n\nLoaded starter packages:\n" + "\n".join(sorted(set(EXPECTED) & loaded)))
        handle.write("\n\nMissing starter packages:\n" + "\n".join(sorted(missing)))
    print(f"extension gate: {len(set(EXPECTED) & loaded)} / {len(EXPECTED)} bundles loaded")
    for pkg in sorted(missing):
        print(f"MISSING: {pkg}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
