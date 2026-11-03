"""Regressions for real playback proof; no emulator or network is involved."""

import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import anime_smoke as anime


def player(*labels):
    root = ET.Element("hierarchy")
    for label in labels:
        ET.SubElement(root, "node", {
            "content-desc": label, "enabled": "true", "bounds": "[120,290][200,370]",
        })
    return root


class AnimePlaybackTest(unittest.TestCase):
    def setUp(self):
        for target in ("adb", "tap", "screenshot", "time.sleep", "Path.write_text"):
            patcher = patch(f"anime_smoke.{target}")
            mock = patcher.start()
            self.addCleanup(patcher.stop)
            setattr(self, target.replace(".", "_"), mock)
        self.adb.return_value = "Physical size: 320x640"
        self.report = {"source": "AniZone", "catalogue": True, "episodes": True, "playback": False}

    def test_clock_advances_after_resuming_the_actual_play_button(self):
        before = player("Eiji", "Play", "0:10 / 49:49")
        after = player("Eiji", "Play", "0:16 / 49:49")
        with patch.object(anime, "paused_player", side_effect=[before, after]):
            result = anime.verify_playback("AniZone", "Eiji", self.report)
        self.assertTrue(result["playback"])
        self.assertEqual((result["position_before"], result["position"], result["duration"]), (10, 16, 2989))
        self.tap.assert_called_once_with(before[1], wait=6)
        self.assertEqual(len(result["observations"]), 2)
        self.assertEqual(self.Path_write_text.call_count, 2)
        self.screenshot.assert_any_call("anime-AniZone-playback-before.png")
        self.screenshot.assert_any_call("anime-AniZone-playback.png")

    def test_stationary_player_never_passes(self):
        root = player("Eiji", "Play", "1:52 / 49:49")
        with patch.object(anime, "paused_player", return_value=root), \
                patch.object(anime.time, "monotonic", side_effect=[0, 0, 1, 101]):
            with self.assertRaisesRegex(RuntimeError, "did not advance"):
                anime.verify_playback("AniZone", "Eiji", self.report)
        self.assertFalse(self.report["playback"])
        self.assertEqual(len(self.report["observations"]), 2)

    def test_sample_cannot_pass_even_with_a_real_title_and_clock(self):
        root = player("Eiji", "Play", "Sample video", "0:16 / 49:49")
        with patch.object(anime, "paused_player", return_value=root):
            with self.assertRaisesRegex(RuntimeError, "sample playback"):
                anime.verify_playback("AniZone", "Eiji", self.report)
        self.tap.assert_not_called()
        self.assertFalse(self.report["playback"])

    def test_changed_video_duration_is_not_advancement(self):
        with patch.object(anime, "paused_player", side_effect=[
                player("Eiji", "Play", "0:10 / 49:49"),
                player("Eiji", "Play", "0:16 / 24:00")]):
            with self.assertRaisesRegex(RuntimeError, "changed duration"):
                anime.verify_playback("AniZone", "Eiji", self.report)
        self.assertFalse(self.report["playback"])

    def test_unrelated_title_or_hidden_play_button_cannot_pass(self):
        for root in (player("Other anime", "Play", "0:16 / 49:49"),
                     player("Eiji", "Pause", "0:16 / 49:49")):
            with self.subTest(labels=[node.get("content-desc") for node in root]), \
                    patch.object(anime, "paused_player", return_value=root), \
                    patch.object(anime.time, "monotonic", side_effect=[0, 0, 101]):
                with self.assertRaisesRegex(RuntimeError, "did not advance"):
                    anime.verify_playback("AniZone", "Eiji", self.report)
        self.tap.assert_not_called()
        self.assertFalse(self.report["playback"])

    def test_pause_capture_uses_only_backdrop_and_play_pause_coordinates(self):
        root = player("Eiji", "Play", "0:10 / 49:49")
        with patch.object(anime, "dump", side_effect=[player(), root]):
            self.assertIs(anime.paused_player(320, 640), root)
        taps = [call.args for call in self.adb.call_args_list]
        self.assertEqual(taps, [
            ("shell", "input", "tap", "160", "213"),
            ("shell", "input", "tap", "160", "320"),
        ] * 2)

    def test_completed_catalogue_stage_survives_later_failure(self):
        def check(name, *, play, report):
            report.update(catalogue=True, title="Eiji")
            raise RuntimeError("episodes unavailable")

        with patch.object(anime, "SOURCES", ("AniZone",)), \
                patch.object(anime, "check_source", side_effect=check):
            self.assertEqual(anime.main(), 1)
        saved = json.loads(self.Path_write_text.call_args.args[0])[0]
        self.assertTrue(saved["catalogue"])
        self.assertFalse(saved["episodes"])
        self.assertFalse(saved["playback"])
        self.assertEqual(saved["error"], "episodes unavailable")

    def test_real_source_check_records_each_stage_before_a_player_failure(self):
        catalogue = player("Eiji\nAnime")
        catalogue[0].set("clickable", "true")
        report = {"source": "AniZone", "catalogue": False, "episodes": False, "playback": False}
        with patch.object(anime, "dismiss_anr"), \
                patch.object(anime, "wait_for", return_value=player("Browse")[0]), \
                patch.object(anime, "tap_tab"), \
                patch.object(anime, "select_source"), \
                patch.object(anime, "dump", side_effect=[catalogue, player("Watch now")]), \
                patch.object(anime, "verify_playback", side_effect=RuntimeError("video stalled")):
            with self.assertRaisesRegex(RuntimeError, "video stalled"):
                anime.check_source("AniZone", play=True, report=report)
        self.assertEqual(report, {"source": "AniZone", "title": "Eiji", "catalogue": True,
                                  "episodes": True, "playback": False})

    def test_successful_source_does_not_erase_another_sources_failure(self):
        def check(name, *, play, report):
            report.update(catalogue=True, episodes=True)
            if name == "AniZone":
                report["playback"] = True
            else:
                self.assertFalse(play)
                raise RuntimeError("rate limited")

        with patch.object(anime, "SOURCES", ("AniZone", "AnimePahe")), \
                patch.object(anime, "check_source", side_effect=check):
            self.assertEqual(anime.main(), 0)
        saved = json.loads(self.Path_write_text.call_args.args[0])
        self.assertTrue(saved[0]["playback"])
        self.assertEqual(saved[1]["error"], "rate limited")


if __name__ == "__main__":
    unittest.main()
