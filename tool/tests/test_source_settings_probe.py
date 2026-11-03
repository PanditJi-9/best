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

    def test_a_source_chip_behind_the_sheet_is_not_a_setting_row(self):
        # Run 41617910370 tapped the chip above the scrim, which dismissed the
        # sheet, so the choice dialog never opened.
        root = hierarchy(
            ("مانجا ليك", "true", "[143,223][242,267]"),
            ("These controls come from the extension itself", "false",
             "[20,345][300,395]"),
            ("الخادم البديل المفضل\nmangalik.net", "true", "[20,400][300,460]"),
            ("Browse", "true", "[128,576][192,640]"),
        )

        rows = probe.setting_rows(root)

        self.assertEqual(
            [probe.label(node) for node in rows],
            ["الخادم البديل المفضل\nmangalik.net"],
        )

    def test_dialog_choices_ignore_the_sheet_row_it_opened_from(self):
        sheet = hierarchy(
            ("الخادم البديل المفضل\nmangalik.net", "true", "[20,400][300,460]"),
        )
        before = probe.clickable_labels(sheet)
        dialog = hierarchy(
            ("الخادم البديل المفضل\nmangalik.net", "true", "[20,400][300,460]"),
            ("mangalik.net", "true", "[40,200][280,260]"),
            ("lekmanga.online", "true", "[40,260][280,320]"),
            ("Cancel", "true", "[240,340][300,380]"),
        )

        options = probe.dialog_options(dialog, before)

        self.assertEqual(
            [probe.label(node) for node in options],
            ["mangalik.net", "lekmanga.online"],
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
