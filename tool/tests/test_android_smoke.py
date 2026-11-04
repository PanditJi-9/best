"""Offline regression tests for the emulator tooling; never connect to a phone."""

from pathlib import Path
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

TOOL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
import android_smoke as smoke
import anime_smoke
import extension_probe as probe


def hierarchy(*labels):
    root = ET.Element("hierarchy")
    for label in labels:
        ET.SubElement(root, "node", {
            "content-desc": label, "bounds": "[20,130][120,174]",
        })
    return root


class SmokeToolsTest(unittest.TestCase):
    def test_exact_leaf_is_not_discarded_as_falsey(self):
        root = hierarchy("Browse", "Browse Tab 3 of 5")
        self.assertIs(smoke.find_any(root, "Browse"), root[0])

    def test_navigation_prefix_precedes_paragraph_substring(self):
        root = hierarchy("Add a work from Browse", "Browse Tab 3 of 5")
        self.assertIs(smoke.find_any(root, "Browse"), root[1])

    def test_substring_leaf_is_not_discarded(self):
        root = hierarchy("Series — Episode 1")
        self.assertIs(smoke.find_any(root, "Episode 1"), root[0])

    def test_absent_label_returns_none(self):
        self.assertIsNone(smoke.find_any(hierarchy("Library"), "Browse"))

    @patch.object(smoke.time, "sleep")
    @patch.object(smoke, "adb", return_value="Physical size: 320x640")
    @patch.object(smoke, "tap")
    def test_source_selection_walks_more_than_one_viewport(self, tap, adb, _sleep):
        # The Manga tab lists sources vertically, so walking to a source that
        # is off screen means swiping up on the same x, not sideways along a
        # chip row.
        pages = [hierarchy("All sources"), hierarchy("MangaFire"),
                 hierarchy("AnimePahe"), hierarchy("Best Guide")]
        with patch.object(smoke, "dump", side_effect=pages):
            smoke.select_source("Best Guide")
        self.assertEqual(tap.call_count, 1)
        self.assertIs(tap.call_args.args[0], pages[-1][0])
        swipes = [call for call in adb.call_args_list if "swipe" in call.args]
        self.assertEqual(len(swipes), 3)
        self.assertTrue(all(call.args[3] == call.args[5] for call in swipes))
        self.assertTrue(all(call.args[4] == "460" for call in swipes))

    @patch.object(smoke, "adb")
    @patch.object(smoke, "tap")
    def test_source_already_visible_needs_no_row_anchor(self, tap, adb):
        root = hierarchy("AniZone")
        with patch.object(smoke, "dump", return_value=root):
            smoke.select_source("AniZone")
        tap.assert_called_once()
        adb.assert_not_called()

    @patch.object(smoke, "adb")
    @patch.object(smoke, "tap")
    def test_source_tile_with_avatar_initial_is_matched_by_name(self, tap, adb):
        # A Manga-tab tile merges its avatar initial, name and language into a
        # single semantics node, so the label never starts with the name.
        root = ET.Element("hierarchy")
        ET.SubElement(root, "node", {
            "content-desc": "م\nمانجا ليك\nManga · AR · Latest",
            "clickable": "true",
        })
        with patch.object(smoke, "dump", return_value=root):
            smoke.select_source("مانجا ليك")
        self.assertIs(tap.call_args.args[0], root[0])
        adb.assert_not_called()

    @patch.object(smoke, "adb")
    @patch.object(smoke, "tap")
    def test_source_qualifier_does_not_hide_the_chip(self, tap, adb):
        root = hierarchy("AnimeKai (Unoriginal)")
        with patch.object(smoke, "dump", return_value=root):
            smoke.select_source("AnimeKai")
        self.assertIs(tap.call_args.args[0], root[0])
        adb.assert_not_called()

    def test_gate_requires_loaded_package_not_builtin_label_or_failure(self):
        log = "\n".join([
            "I/BestExtensions( 123): loaded AniZone (42) from eu.kanade.tachiyomi.animeextension.all.anizone",
            "W/BestExtensions( 123): extension eu.kanade.tachiyomi.animeextension.en.animepahe failed to load",
            "Browse MangaDex 5 sources ready",
        ])
        self.assertEqual(probe.loaded_packages(log), {probe.ANIME_PACKAGES[0]})

    def test_regression_selections_are_not_a_mandatory_app_starter_set(self):
        dart = (TOOL.parent / "apps/best_app/lib/src/extension_host.dart").read_text()
        for package in probe.EXPECTED:
            self.assertNotIn(f"'{package}'", dart)
        self.assertEqual(len(probe.EXPECTED), 9)
        providers = (TOOL.parent / "apps/best_app/lib/src/providers.dart").read_text()
        self.assertNotIn("ensureStarterSet", providers)

    @patch.object(probe.time, "sleep")
    @patch.object(probe, "adb")
    @patch.object(probe, "tap")
    @patch.object(probe, "wait_for")
    def test_directory_activation_searches_by_package_and_requires_host_load(self, wait, tap, adb, _sleep):
        package = probe.EXPECTED[0]
        root = hierarchy("Search")
        root[0].set("class", "android.widget.EditText")
        pages = [root, hierarchy("Activate"), hierarchy("Trust & activate")]
        adb.return_value = f"I/BestExtensions: loaded Test (42) from {package}"
        with patch.object(probe, "dump", side_effect=pages):
            probe.activate_from_directory(package)
        self.assertIn(unittest.mock.call("shell", "input", "text", package), adb.call_args_list)
        self.assertEqual(tap.call_count, 4)
        wait.assert_called_once_with("Cancel")

    def test_player_clock_handles_minutes_and_hours(self):
        self.assertEqual(anime_smoke.playback_clock(hierarchy("0:12 / 24:00")), (12, 1440))
        self.assertEqual(anime_smoke.playback_clock(hierarchy("1:02:03 / 2:00:00")), (3723, 7200))
        self.assertIsNone(anime_smoke.playback_clock(hierarchy("Sample video")))

    @patch.object(smoke.time, "sleep")
    def test_failed_dump_cannot_reuse_a_stale_hierarchy(self, _sleep):
        xml = '<?xml version="1.0"?><hierarchy><node content-desc="Play" /></hierarchy>'

        def device(*args, **kwargs):
            nonlocal xml
            if args == ("shell", "rm", "-f", "/sdcard/window.xml"):
                xml = ""
            return xml if args == ("shell", "cat", "/sdcard/window.xml") else ""

        with patch.object(smoke, "adb", side_effect=device) as adb:
            with self.assertRaisesRegex(SystemExit, "no hierarchy"):
                smoke.dump()
        self.assertEqual(adb.call_args_list[0].args,
                         ("shell", "rm", "-f", "/sdcard/window.xml"))

    def test_runtime_workflows_use_bash_for_the_generated_gradle_wrapper(self):
        # Recent Flutter templates generate a Bash wrapper (arrays), not a
        # POSIX-sh script. Calling it with sh fails before any JVM test runs.
        for name in ("ci.yml", "android-smoke.yml"):
            workflow = (TOOL.parent / ".github/workflows" / name).read_text()
            self.assertIn("bash ./gradlew :app:testReleaseUnitTest --no-daemon", workflow)
            self.assertNotIn("\n          sh ./gradlew :app:testReleaseUnitTest", workflow)
            self.assertIn("TEST-app.best.best_app.ext.RuntimeAbiTest.xml", workflow)

    def test_runtime_workflows_explicitly_enable_release_unit_tests_on_agp9(self):
        # AGP 9 enables only the tested build type (debug) by default, so the
        # release task disappears unless this default is explicitly overridden.
        command = ("bash ./gradlew :app:testReleaseUnitTest --no-daemon "
                   "-Pandroid.onlyEnableUnitTestForTheTestedBuildType=false")
        for name in ("ci.yml", "android-smoke.yml"):
            workflow = (TOOL.parent / ".github/workflows" / name).read_text()
            self.assertIn(command, workflow)

    def test_single_shell_keeps_failure_status_and_always_collects_logs(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            stubs = {
                "adb": '#!/bin/sh\ncase "$*" in\n'
                       '  *pidof*) echo 123;;\n'
                       '  "logcat -d -v brief") echo "W/BestExtensions: diagnostic"; '
                       'echo "  at app.best.ExtensionHost.loadSources(ExtensionHost.kt:10)";;\n'
                       'esac\n',
                "sleep": '#!/bin/sh\nexit 0\n',
                "python3": '#!/bin/sh\necho "$2" >> executed.txt\n'
                           'case "$2" in\n'
                           '  *extension_probe.py) exit 7;;\n'
                           '  *) exit 0;;\n'
                           'esac\n',
            }
            for name, body in stubs.items():
                path = work / name
                path.write_text(body)
                path.chmod(0o755)
            result = subprocess.run(
                ["sh", str(TOOL / "run_android_smoke.sh")],
                cwd=work,
                env={**os.environ, "PATH": f"{directory}:{os.environ['PATH']}"},
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 7, result.stderr)
            self.assertEqual((work / "executed.txt").read_text().splitlines(), [
                "tool/extension_probe.py", "tool/manga_smoke.py",
                "tool/anime_smoke.py", "tool/android_smoke.py",
            ])
            self.assertIn("ExtensionHost.kt:10", (work / "logcat.txt").read_text())
            self.assertIn("BestExtensions", (work / "extensions.log").read_text())


if __name__ == "__main__":
    unittest.main()
