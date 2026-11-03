"""Offline regressions for the extension settings gate; never touches a phone."""

import sys
from pathlib import Path
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import source_settings_probe as probe


def hierarchy(*items):
    root = ET.Element("hierarchy")
    for label, clickable, bounds in items:
        ET.SubElement(
            root,
            "node",
            {"content-desc": label, "clickable": clickable, "bounds": bounds},
        )
    return root


class SourceSettingsProbeTest(unittest.TestCase):
    def test_chrome_and_the_hint_are_not_setting_rows(self):
        root = hierarchy(
            ("Source settings", "true", "[0,0][60,40]"),
            ("Close", "true", "[260,0][320,40]"),
            ("These controls come from the extension itself", "true",
             "[0,60][320,120]"),
            ("الخادم البديل المفضل\nmangalik.net", "true", "[0,140][320,200]"),
        )

        rows = probe.setting_rows(root)

        self.assertEqual(
            [probe.label(node) for node in rows],
            ["الخادم البديل المفضل\nmangalik.net"],
        )

    def test_rows_keep_the_order_the_extension_declared(self):
        root = hierarchy(
            ("second\nvalue-b", "true", "[0,300][320,360]"),
            ("first\nvalue-a", "true", "[0,100][320,160]"),
        )

        rows = probe.setting_rows(root)

        self.assertEqual(
            [probe.label(node) for node in rows],
            ["first\nvalue-a", "second\nvalue-b"],
        )


if __name__ == "__main__":
    unittest.main()
