"""Offline regressions for real manga evidence; never connect to a phone."""

import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import manga_smoke as manga


def hierarchy(*labels):
    root = ET.Element("hierarchy")
    for label in labels:
        ET.SubElement(root, "node", {"content-desc": label, "clickable": "true", "enabled": "true"})
    return root


class MangaSmokeTest(unittest.TestCase):
    def test_anime_cards_or_plain_labels_cannot_pass_a_manga_catalogue(self):
        for root in (hierarchy("Eiji\nAnime"), hierarchy("MangaDex"), hierarchy("Manga")):
            self.assertIsNone(manga.manga_card(root))
        root = hierarchy("Real title\nManhwa")
        self.assertIs(manga.manga_card(root), root[0])

    def test_reader_requires_a_positive_real_page_count_not_series_labels(self):
        self.assertIsNone(manga.reader_pages(hierarchy("Real title", "Start reading")))
        self.assertEqual(manga.reader_pages(hierarchy("Page 1 of 23")), 23)
        self.assertIsNone(manga.reader_pages(hierarchy("Page 1 of 0")))
        self.assertIsNone(manga.reader_pages(hierarchy("Page 0 of 23")))
        self.assertIsNone(manga.reader_pages(hierarchy("Page 24 of 23")))
        self.assertEqual(manga.reader_pages(hierarchy("Pages 2–3 of 23")), 23)

    def test_page_counter_alone_is_not_image_decode_proof(self):
        self.assertEqual(manga.page_image_state(hierarchy("Page 1 of 23")), "pending")
        self.assertEqual(manga.page_image_state(hierarchy("Page image")), "ready")
        self.assertEqual(
            manga.page_image_state(hierarchy("This page did not load")), "failed")
        self.assertEqual(manga.page_image_state(hierarchy(
            "Page image", "This page did not load")), "failed")

    def test_hidden_chrome_is_revealed_without_substituting_a_counter_for_a_decoded_page(self):
        hidden = hierarchy("Page image")
        revealed = hierarchy("Real title", "Page 1 of 23", "Page image", "Reader settings")
        with patch.object(manga, "tap") as tap, \
                patch.object(manga, "dump", return_value=revealed):
            self.assertIs(manga.reveal_reader_controls(hidden), revealed)
        tap.assert_called_once_with(hidden[0], wait=0.2)
        with patch.object(manga, "tap") as tap:
            self.assertEqual(manga.reveal_reader_controls(hierarchy("Loading"))[0].get("content-desc"), "Loading")
        tap.assert_not_called()

    def test_layout_selection_uses_the_toolkit_and_dismisses_its_modal(self):
        for tools, mode in (("Reader settings", "Vertical"),
                            ("إعدادات القارئ", "عمودي")):
            with self.subTest(tools=tools):
                root = hierarchy("Real title", "Page 1 of 23", "Page image", tools)
                choice = hierarchy(mode)[0]
                with patch.object(manga, "tap") as tap, \
                        patch.object(manga, "wait_for", return_value=choice) as wait, \
                        patch.object(manga, "adb") as adb, \
                        patch.object(manga.time, "sleep"), \
                        patch.object(manga, "dump", return_value=root):
                    self.assertIs(manga.choose_reader_layout(root, vertical=True), root)
                self.assertIs(tap.call_args_list[0].args[0], root[3])
                self.assertIs(tap.call_args_list[1].args[0], choice)
                wait.assert_called_once_with(mode, timeout=20, scrolls=8)
                adb.assert_called_once_with("shell", "input", "keyevent", "4")

    def test_a_missing_toolkit_cannot_pass_a_layout_check(self):
        with self.assertRaisesRegex(RuntimeError, "toolkit button"):
            manga.choose_reader_layout(hierarchy("Page image"), vertical=True)

    def test_runtime_contract_failures_are_not_mislabelled_as_site_outages(self):
        lines = ["W/BestExtensions: UncaughtExceptionInterceptor must be present in default client",
                 "W/BestExtensions: java.lang.AbstractMethodError: getMangaDetails",
                 "W/BestExtensions: java.lang.NoClassDefFoundError: MissingClass",
                 "W/BestExtensions: java.io.IOException: rate limited",
                 "I/OtherApp: ClassNotFoundException"]
        self.assertEqual(manga.runtime_contract_errors("\n".join(lines)), lines[:3])

    def test_navigation_uses_the_actual_start_and_continue_reading_labels(self):
        labels = json.loads((Path(__file__).resolve().parents[2] /
                             "apps/best_app/lib/src/l10n/app_en.arb").read_text())
        for label in (labels["startReading"], labels["continueReading"]):
            with self.subTest(label=label):
                report = {"source": "MangaDex", "catalogue": False, "chapters": False, "reader": False}
                screens = [hierarchy("Real title\nManga"), hierarchy(label),
                            hierarchy("Real title", "Page 1 of 23", "Page image",
                                      "Reader settings")]
                seen = {"count": 0}

                def fake_dump():
                    screen = screens[min(seen["count"], len(screens) - 1)]
                    seen["count"] += 1
                    return screen

                with patch.object(manga, "adb"), patch.object(manga.time, "sleep"), \
                        patch.object(manga, "dismiss_anr"), \
                        patch.object(manga, "wait_for", side_effect=lambda wanted, **kwargs:
                                     hierarchy(wanted)[0]), \
                        patch.object(manga, "tap_tab"), \
                        patch.object(manga, "open_sources"), \
                        patch.object(manga, "select_source") as select, \
                        patch.object(manga, "dump", side_effect=fake_dump), \
                        patch.object(manga, "tap") as tap, \
                        patch.object(manga, "screenshot") as screenshot, \
                        patch.object(manga, "swipe_up") as swipe, \
                        patch.object(manga.Path, "write_text"):
                    manga.check_source("MangaDex", report)
                select.assert_called_once_with("MangaDex")
                self.assertIs(tap.call_args_list[1].args[0], screens[1][0])
                self.assertIs(tap.call_args_list[2].args[0], screens[2][3])
                self.assertEqual(tap.call_args_list[3].args[0].get("content-desc"), "Vertical")
                self.assertEqual(tap.call_args_list[5].args[0].get("content-desc"), "Paged")
                swipe.assert_not_called()
                self.assertTrue(report["catalogue"])
                self.assertTrue(report["chapters"])
                self.assertTrue(report["reader"])
                self.assertTrue(report["vertical"])
                self.assertEqual(report["page_count"], 23)
                self.assertEqual(screenshot.call_count, 4)

    def test_real_reader_evidence_records_each_stage_and_keeps_site_failure(self):
        def check(name, report):
            report.update(catalogue=True, title="Real title")
            if name == "MangaDex":
                report.update(chapters=True, reader=True, page_count=23)
            else:
                raise RuntimeError("rate limited")
        with patch.object(manga, "SOURCES", ("MangaDex", "MangaFire")), \
                patch.object(manga, "check_source", side_effect=check), \
                patch.object(manga, "screenshot"), patch.object(manga, "adb", return_value=""), \
                patch.object(manga.Path, "write_text") as save:
            self.assertEqual(manga.main(), 0)
        report = json.loads(save.call_args_list[-2].args[0])
        self.assertTrue(report[0]["reader"])
        self.assertTrue(report[1]["catalogue"])
        self.assertEqual(report[1]["error"], "rate limited")

    def test_successful_reader_cannot_hide_a_runtime_abi_failure(self):
        def check(name, report):
            report.update(catalogue=True, chapters=True, reader=True)
        with patch.object(manga, "SOURCES", ("MangaDex",)), \
                patch.object(manga, "check_source", side_effect=check), \
                patch.object(manga, "adb", return_value="W/BestExtensions: java.lang.NoSuchMethodError"), \
                patch.object(manga.Path, "write_text"):
            self.assertEqual(manga.main(), 1)

    def test_workflow_runs_the_manga_gate_and_keeps_its_artifacts(self):
        root = Path(__file__).resolve().parents[2]
        self.assertIn("tool/manga_smoke.py", (root / "tool/run_android_smoke.sh").read_text())
        workflow = (root / ".github/workflows/android-smoke.yml").read_text()
        for artifact in ("manga-*.png", "manga-*.xml", "manga-results.json", "manga-runtime-errors.json"):
            self.assertIn(artifact, workflow)


if __name__ == "__main__":
    unittest.main()
