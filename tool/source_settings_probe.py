#!/usr/bin/env python3
"""Prove an extension's own settings screen opens, changes and persists.

A source that only knows its first domain is a source that dies when that
domain is blocked. The host builds the `androidx.preference` screen the
extension declares, so this gate opens it through the real app, picks another
server, and re-opens the sheet to prove the extension read the new value back.
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from pathlib import Path

from android_smoke import (
    ACTIVITY, PACKAGE, adb, debug_texts, dismiss_anr, dump, find_any, nodes,
    screenshot, select_source, tap, wait_for,
)

SOURCE = os.environ.get("SOURCE_SETTINGS_SOURCE", "").strip()

HINTS = ("These controls come from the extension itself",
         "هذه الخيارات تأتي من الإضافة نفسها")
SETTINGS = ("Source settings", "إعدادات المصدر")
SAVED = ("Setting saved", "حُفظ الإعداد")
CANCEL = ("Cancel", "إلغاء")
CLOSE = ("Close", "إغلاق")


def label(node) -> str:
    return ((node.get("text") or "") + " " + (node.get("content-desc") or "")).strip()


def first_label(root, wanted: tuple[str, ...]):
    for text in wanted:
        node = find_any(root, text)
        if node is not None:
            return node
    return None


def visible_texts(root) -> list[str]:
    seen: list[str] = []
    for node in nodes(root):
        for value in (node.get("text") or "", node.get("content-desc") or ""):
            value = value.strip()
            if value and value not in seen:
                seen.append(value)
    return seen


def open_sheet() -> None:
    deadline = time.monotonic() + 30
    gear = None
    while time.monotonic() < deadline:
        gear = first_label(dump(), SETTINGS)
        if gear is not None:
            break
        time.sleep(1.5)
    if gear is None:
        debug_texts(dump())
        raise RuntimeError("the source settings button did not render")
    tap(gear, wait=2.5)
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        root = dump()
        if any(any(hint in value for value in visible_texts(root)) for hint in HINTS):
            return
        time.sleep(1.5)
    debug_texts(root)
    raise RuntimeError("the settings sheet did not open")


def setting_rows(root):
    """Clickable rows inside the sheet, top to bottom, excluding chrome."""
    rows = []
    for node in nodes(root):
        if node.get("clickable") != "true":
            continue
        value = label(node)
        if not value:
            continue
        if any(chrome in value for chrome in SETTINGS + CLOSE):
            continue
        if any(hint in value for hint in HINTS):
            continue
        if any(cancel in value for cancel in CANCEL):
            continue
        rows.append(node)
    def top(node) -> int:
        numbers = [int(value) for value in re.findall(r"\d+", node.get("bounds", ""))]
        return numbers[1] if len(numbers) == 4 else 0

    rows.sort(key=top)
    return rows


def main() -> int:
    if not SOURCE:
        print("SOURCE_SETTINGS_SOURCE is empty; nothing to check")
        return 0

    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(8)
    dismiss_anr()
    tap(wait_for("Browse", timeout=40), wait=4)
    select_source(SOURCE)
    time.sleep(2)

    open_sheet()
    screenshot("source-settings.png")
    root = dump()
    rows = setting_rows(root)
    if not rows:
        debug_texts(root)
        raise RuntimeError(f"{SOURCE} exposed no settings rows")

    tap(rows[0], wait=2)
    deadline = time.monotonic() + 30
    dialog = None
    while time.monotonic() < deadline:
        root = dump()
        if first_label(root, CANCEL) is not None:
            dialog = root
            break
        time.sleep(1.5)
    if dialog is None:
        debug_texts(root)
        raise RuntimeError("the setting did not open a choice dialog")

    cancel = first_label(dialog, CANCEL)
    options = [node for node in setting_rows(dialog)
               if node is not cancel and label(node) not in CANCEL]
    if len(options) < 2:
        debug_texts(dialog)
        raise RuntimeError("the setting offered fewer than two choices")
    chosen = label(options[1]).splitlines()[0]
    screenshot("source-settings-choices.png")
    tap(options[1], wait=1.5)

    deadline = time.monotonic() + 25
    saved = False
    while time.monotonic() < deadline:
        root = dump()
        if any(saved_text in value
               for value in visible_texts(root)
               for saved_text in SAVED):
            saved = True
            break
        time.sleep(1)
    if not saved:
        debug_texts(root)
        raise RuntimeError("the extension did not confirm the saved setting")

    close = first_label(dump(), CLOSE)
    if close is not None:
        tap(close, wait=2)
    open_sheet()
    persisted = any(chosen in value for value in visible_texts(dump()))
    screenshot("source-settings-persisted.png")
    Path("source-settings.json").write_text(json.dumps({
        "source": SOURCE,
        "rows": len(rows),
        "chosen": chosen,
        "saved": saved,
        "persisted": persisted,
    }, ensure_ascii=False, indent=2))
    if not persisted:
        debug_texts(dump())
        raise RuntimeError(f"the extension did not keep {chosen!r}")
    print(f"settings gate: {SOURCE} switched to {chosen} and kept it")
    return 0


if __name__ == "__main__":
    sys.exit(main())
