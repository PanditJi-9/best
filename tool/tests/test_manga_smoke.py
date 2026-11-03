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
        self.assertEqual(manga.reader_pages(hierarchy("Page 1 of 0")), 0)

    def test_page_counter_alone_is_not_image_decode_proof(self):
        self.assertEqual(manga.page_image_state(hierarchy("Page 1 of 23")), "pending")
        self.assertEqual(manga.page_image_state(hierarchy("Page image")), "ready")
        self.assertEqual(
            manga.page_image_state(hierarchy("This page did not load")), "failed")

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
                           hierarchy("Real title", "Page 1 of 23", "Page image")]
                seen = {"count": 0}

                def fake_dump():
                    screen = screens[min(seen["count"], len(screens) - 1)]
                    seen["count"] += 1
                    return screen

                with patch.object(manga, "adb"), patch.object(manga.time, "sleep"), \
                        patch.object(manga, "dismiss_anr"), patch.object(manga, "wait_for"), \
                        patch.object(manga, "select_source") as select, \
                        patch.object(manga, "dump", side_effect=fake_dump), \
                        patch.object(manga, "tap") as tap, \
                        patch.object(manga, "screenshot") as screenshot, \
                        patch.object(manga, "swipe_up") as swipe, \
                        patch.object(manga.Path, "write_text"):
                    manga.check_source("MangaDex", report)
                select.assert_called_once_with("MangaDex")
                self.assertIs(tap.call_args.args[0], screens[1][0])
                swipe.assert_not_called()
                self.assertTrue(report["catalogue"])
                self.assertTrue(report["chapters"])
                self.assertTrue(report["reader"])
                self.assertEqual(report["page_count"], 23)
                self.assertEqual(screenshot.call_count, 3)

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
