#!/usr/bin/env python3
"""Check selected real manga catalogues, chapters and the reader on Actions.

These are test selections, never application defaults. Keep site failures in
the report and fail on runtime ABI errors even if another site answers.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys
import time
import xml.etree.ElementTree as ET

from android_smoke import (
    ACTIVITY, PACKAGE, adb, debug_texts, dismiss_anr, dump, find_any, nodes,
    screenshot, select_source, swipe_up, tap, wait_for,
)
from anime_smoke import error_on_screen

SOURCES = ("MangaDex", "MangaFire", "Weeb Central", "MangaKatana")


def manga_card(root):
    return next((node for node in nodes(root)
                 if node.get("clickable") == "true"
                 and len((node.get("content-desc") or "").splitlines()) > 1
                 and any(kind in (node.get("content-desc") or "").splitlines()
                         for kind in ("Manga", "Manhwa", "Manhua", "Webtoon"))), None)


def reader_pages(root) -> int | None:
    for node in nodes(root):
        text = (node.get("text") or "") + " " + (node.get("content-desc") or "")
        match = re.search(r"\bPage \d+ of (\d+)\b", text)
        if match:
            return int(match.group(1))
    return None


def runtime_contract_errors(log: str) -> list[str]:
    return [line for line in log.splitlines()
            if "BestExtensions" in line and any(error in line for error in (
                "must be present in default client", "NoSuchMethodError",
                "AbstractMethodError", "NoClassDefFoundError", "ClassNotFoundException"))]


def check_source(name: str, report: dict) -> None:
    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(6)
    dismiss_anr()
    tap(wait_for("Browse", timeout=35), wait=3)
    select_source(name)
    deadline = time.monotonic() + 60
    card = None
    while time.monotonic() < deadline:
        root = dump()
        error = error_on_screen(root)
        if error:
            raise RuntimeError(f"{name} catalogue: {error}")
        card = manga_card(root)
        if card is not None:
            break
        time.sleep(2)
    if card is None:
        debug_texts(root)
        raise RuntimeError(f"{name} returned no visible manga cards")
    report.update(catalogue=True, title=card.get("content-desc", "").splitlines()[0])
    screenshot(f"manga-{name}-catalogue.png")
    tap(card, wait=5)
    deadline = time.monotonic() + 80
    cta = None
    while time.monotonic() < deadline:
        root = dump()
        error = error_on_screen(root)
        if error:
            raise RuntimeError(f"{name} chapters: {error}")
        cta = find_any(root, "Start reading")
        if cta is None:
            cta = find_any(root, "Continue reading")
        if cta is not None and cta.get("enabled") == "true":
            break
        swipe_up()
    if cta is None or cta.get("enabled") != "true":
        raise RuntimeError(f"{name} did not offer a readable chapter")
    report["chapters"] = True
    screenshot(f"manga-{name}-chapters.png")
    tap(cta, wait=12)
    deadline = time.monotonic() + 70
    while time.monotonic() < deadline:
        root = dump()
        error = error_on_screen(root)
        if error:
            raise RuntimeError(f"{name} pages: {error}")
        count = reader_pages(root)
        if count is not None and count > 0 and find_any(root, report["title"]) is not None:
            report.update(reader=True, page_count=count)
            Path(f"manga-{name}-reader.xml").write_text(ET.tostring(root, encoding="unicode"))
            screenshot(f"manga-{name}-reader.png")
            return  # Inspect the screenshot separately; a page count is not image-decode proof.
        time.sleep(2)
    debug_texts(root)
    raise RuntimeError(f"{name} reader did not expose real chapter pages")


def main() -> int:
    reports = []
    for name in SOURCES:
        report = {"source": name, "catalogue": False, "chapters": False, "reader": False}
        reports.append(report)
        try:
            check_source(name, report)
        except (RuntimeError, SystemExit) as error:
            report["error"] = str(error)
            screenshot(f"manga-{name}-failure.png")
        finally:
            Path("manga-results.json").write_text(json.dumps(reports, ensure_ascii=False, indent=2))
    errors = runtime_contract_errors(adb("logcat", "-d", "-v", "brief", check=False))
    Path("manga-runtime-errors.json").write_text(json.dumps(errors, indent=2))
    print(json.dumps(reports, ensure_ascii=False, indent=2))
    if errors:
        print("\n".join(errors))
    return 0 if any(report["reader"] for report in reports) and not errors else 1


if __name__ == "__main__":
    sys.exit(main())
