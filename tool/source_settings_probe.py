#!/usr/bin/env python3
"""Prove an extension's own settings screen opens, changes and persists.

A source that only knows its first domain is a source that dies when that
domain is blocked. The host builds the `androidx.preference` screen the
extension declares, so this gate opens it through the real app, picks another
server, and re-opens the sheet to prove the extension read the new value back.

The semantics tree of a modal sheet still contains the screen underneath it.
Selecting every clickable node therefore taps a source chip behind the scrim,
which dismisses the sheet instead of opening the setting — exactly what run
41617910370 did. Rows are therefore restricted to the sheet region (below its
hint) and dialog choices to nodes that were not clickable before the dialog.
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
    screenshot, select_source, tap, tap_tab, wait_for,
)

SOURCE = os.environ.get("SOURCE_SETTINGS_SOURCE", "").strip()

HINTS = ("These controls come from the extension itself",
         "هذه الخيارات تأتي من الإضافة نفسها")
SETTINGS = ("Source settings", "إعدادات المصدر")
SAVED = ("Setting saved", "حُفظ الإعداد")
CANCEL = ("Cancel", "إلغاء")
CLOSE = ("Close", "إغلاق")
NAV = ("Home", "Library", "Browse", "Downloads", "Settings")


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


def bounds_top(node) -> int:
    numbers = [int(value) for value in re.findall(r"\d+", node.get("bounds", ""))]
    return numbers[1] if len(numbers) == 4 else 0


def hint_top(root) -> int:
    for hint in HINTS:
        node = find_any(root, hint)
        if node is not None:
            return bounds_top(node)
    return 0


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


def setting_rows(root, floor: int | None = None):
    """Clickable rows inside the sheet, top to bottom, excluding chrome.

    `floor` is the sheet's own top. Everything above it belongs to the screen
    behind the modal, so a tap there closes the sheet instead of opening a
    setting.
    """
    if floor is None:
        floor = hint_top(root)
    rows = []
    for node in nodes(root):
        if node.get("clickable") != "true":
            continue
        value = label(node)
        if not value:
            continue
        if any(chrome in value for chrome in SETTINGS + CLOSE + NAV):
            continue
        if any(hint in value for hint in HINTS):
            continue
        if any(cancel in value for cancel in CANCEL):
            continue
        if bounds_top(node) < floor:
            continue
        rows.append(node)
    rows.sort(key=bounds_top)
    return rows


def clickable_labels(root) -> set[str]:
    return {label(node) for node in nodes(root)
            if node.get("clickable") == "true" and label(node)}


def dialog_options(root, before: set[str]):
    """Choices that the dialog added, not the sheet or screen behind it."""
    options = [node for node in nodes(root)
               if node.get("clickable") == "true"
               and label(node)
               and label(node) not in before
               and not any(cancel_text in label(node) for cancel_text in CANCEL)
               and not any(chrome in label(node) for chrome in SETTINGS + CLOSE)]
    options.sort(key=bounds_top)
    return options


def main() -> int:
    if not SOURCE:
        print("SOURCE_SETTINGS_SOURCE is empty; nothing to check")
        return 0

    adb("shell", "am", "force-stop", PACKAGE, check=False)
    adb("shell", "am", "start", "-W", "-n", ACTIVITY)
    time.sleep(8)
    dismiss_anr()
    tap_tab(1)
    select_source(SOURCE)
    time.sleep(2)

    open_sheet()
    screenshot("source-settings.png")
    root = dump()
    rows = setting_rows(root)
    if not rows:
        debug_texts(root)
        raise RuntimeError(f"{SOURCE} exposed no settings rows")

    before = clickable_labels(root)
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

    options = dialog_options(dialog, before)
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
