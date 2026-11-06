"""Offline packaging regressions; fixture ZIPs are not runnable Android APKs."""

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile

TOOL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
import android_apks as apks


def elf(abi):
    elf_class, machine = apks.ELF_ABIS.get(abi, (1, 3))
    header = bytearray(20)
    header[:4] = b"\x7fELF"
    header[4], header[5] = elf_class, 1
    header[18:20] = machine.to_bytes(2, "little")
    return bytes(header)


def fixture_apk(path, abis, *, missing=None, wrong_elf=None):
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("AndroidManifest.xml", b"manifest fixture")
        archive.writestr("classes.dex", b"dex fixture")
        archive.writestr("assets/flutter_assets/assets/curated.json", b"[]")
        for abi in abis:
            for library in ("libflutter.so", "libapp.so", "libquickjs.so"):
                if (abi, library) == missing:
                    continue
                value = elf("x86_64" if (abi, library) == wrong_elf else abi)
                archive.writestr(f"lib/{abi}/{library}", value)


class AndroidApksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="best-apk-tests-")
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name)
        (self.app / "pubspec.yaml").write_text("name: best_app\nversion: 1.4.0+24\n")
        self.source = self.app / "build/app/outputs/apk/release"
        self.source.mkdir(parents=True)
        self.metadata = {"applicationId": apks.PACKAGE, "variantName": "release", "elements": []}
        for label in apks.APK_FILES:
            filename = f"app-{label}-release.apk"
            fixture_apk(self.source / filename,
                        apks.ELF_ABIS if label == "universal" else [label])
            self.metadata["elements"].append({
                "filters": [] if label == "universal" else [{"filterType": "ABI", "value": label}],
                "versionName": "1.4.0", "versionCode": 24, "outputFile": filename,
            })
        self.write_metadata()

    def write_metadata(self):
        (self.source / "output-metadata.json").write_text(json.dumps(self.metadata))

    def test_four_standalone_apks_are_collected_after_one_flutter_build(self):
        with patch.object(apks.subprocess, "run") as run:
            report = apks.build_apks(self.app, "flutter fixture")
        run.assert_called_once_with([
            "flutter fixture", "build", "apk", "--release", "--no-pub", "--split-per-abi",
            "--target-platform", "android-arm,android-arm64,android-x64",
        ], cwd=self.app, check=True)
        destination = self.app / "build/release-apks"
        self.assertEqual(set(path.name for path in destination.glob("*.apk")),
                         set(apks.APK_FILES.values()))
        self.assertEqual(report["versionCode"], 24)
        self.assertEqual(len(report["apks"]), 4)
        self.assertEqual(len((destination / "SHA256SUMS").read_text().splitlines()), 4)
        for label, details in report["apks"].items():
            original = (self.source / f"app-{label}-release.apk").read_bytes()
            self.assertEqual((destination / details["file"]).read_bytes(), original)
            self.assertEqual(details["sha256"], hashlib.sha256(original).hexdigest())
        self.assertEqual(report["apks"]["universal"]["abis"], sorted(apks.ELF_ABIS))

    def test_no_old_universal_file_can_fill_a_missing_current_output(self):
        self.metadata["elements"].pop()
        self.write_metadata()
        old = self.app / "build/app/outputs/flutter-apk"
        old.mkdir(parents=True)
        fixture_apk(old / "app-release.apk", apks.ELF_ABIS)
        with self.assertRaisesRegex(ValueError, "same build"):
            apks.collect_apks(self.app)

    def test_an_arm64_apk_cannot_be_renamed_into_the_universal_output(self):
        self.metadata["elements"][-1]["outputFile"] = "app-arm64-v8a-release.apk"
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, "expected ABIs"):
            apks.collect_apks(self.app)

    def test_abi_version_code_offsets_cannot_break_switching_to_universal(self):
        self.metadata["elements"][0]["versionCode"] = 3024
        self.write_metadata()
        with self.assertRaisesRegex(ValueError, "build number"):
            apks.collect_apks(self.app)

    def test_wrong_package_version_duplicate_or_unsafe_metadata_is_rejected(self):
        for change in ("package", "version", "duplicate", "unsafe"):
            with self.subTest(change=change):
                original = json.loads(json.dumps(self.metadata))
                if change == "package":
                    self.metadata["applicationId"] = "other.app"
                elif change == "version":
                    self.metadata["elements"][0]["versionName"] = "1.3.0"
                elif change == "duplicate":
                    self.metadata["elements"].append(self.metadata["elements"][0])
                else:
                    self.metadata["elements"][0]["outputFile"] = "../outside.apk"
                self.write_metadata()
                with self.assertRaises(ValueError):
                    apks.collect_apks(self.app)
                self.metadata = original
        self.assertFalse((self.app / "build/release-apks").exists())

    def test_missing_native_app_code_is_not_a_complete_apk(self):
        path = self.source / "app-armeabi-v7a-release.apk"
        fixture_apk(path, ["armeabi-v7a"], missing=("armeabi-v7a", "libapp.so"))
        with self.assertRaisesRegex(ValueError, "libapp.so"):
            apks.apk_contents(path, "armeabi-v7a")

    def test_universal_never_advertises_unsupported_32_bit_intel(self):
        path = self.source / "app-universal-release.apk"
        fixture_apk(path, [*apks.ELF_ABIS, "x86"])
        with self.assertRaisesRegex(ValueError, "found.*x86"):
            apks.apk_contents(path, "universal")

    def test_native_dependency_machine_type_must_match_the_apk_label(self):
        path = self.source / "app-arm64-v8a-release.apk"
        fixture_apk(path, ["arm64-v8a"], wrong_elf=("arm64-v8a", "libquickjs.so"))
        with self.assertRaisesRegex(ValueError, "wrong native architecture"):
            apks.apk_contents(path, "arm64-v8a")

    def test_actual_apk_identity_and_established_certificate_are_checked(self):
        certificate = "a" * 64
        badging = f"package: name='{apks.PACKAGE}' versionCode='24' versionName='1.4.0'\n"
        signing = f"Signer #1 certificate SHA-256 digest: {certificate}\n"
        path = self.source / "app-universal-release.apk"
        with patch.object(apks.subprocess, "run", side_effect=[
            Mock(stdout=badging), Mock(stdout=signing),
        ]) as run:
            result = apks.verify_apk(path, "universal", ("1.4.0", 24), certificate,
                                     aapt2="aapt2 fixture", apksigner="apksigner fixture")
        self.assertEqual(result["certificateSha256"], certificate)
        self.assertEqual(run.call_count, 2)

    def test_metadata_cannot_hide_a_mismatched_manifest_or_debug_signature(self):
        path = self.source / "app-universal-release.apk"
        correct = f"package: name='{apks.PACKAGE}' versionCode='24' versionName='1.4.0'\n"
        wrong = correct.replace("versionCode='24'", "versionCode='23'")
        for badging, signing in ((wrong, ""), (correct, "Signer #1 certificate SHA-256 digest: " + "b" * 64)):
            with patch.object(apks.subprocess, "run", side_effect=[Mock(stdout=badging), Mock(stdout=signing)]):
                with self.assertRaises(ValueError):
                    apks.verify_apk(path, "universal", ("1.4.0", 24), "a" * 64,
                                    aapt2="aapt2 fixture", apksigner="apksigner fixture")

    def test_current_sdk_v2_signer_format_and_matching_schemes_are_supported(self):
        certificate = "a" * 64
        badging = f"package: name='{apks.PACKAGE}' versionCode='24' versionName='1.4.0'\n"
        signing = (f"V2 Signer: certificate SHA-256 digest: {certificate}\n"
                   f"V3 Signer: certificate SHA-256 digest: {certificate}\n")
        with patch.object(apks.subprocess, "run", side_effect=[Mock(stdout=badging), Mock(stdout=signing)]):
            report = apks.verify_apk(self.source / "app-universal-release.apk", "universal",
                                     ("1.4.0", 24), certificate,
                                     aapt2="aapt2 fixture", apksigner="apksigner fixture")
        self.assertEqual(report["certificateSha256"], certificate)

    def test_aapt2_compile_sdk_codename_cannot_overwrite_the_package_name(self):
        certificate = "a" * 64
        badging = (f"package: name='{apks.PACKAGE}' versionCode='24' versionName='1.4.0' "
                   "platformBuildVersionName='16' compileSdkVersion='36' "
                   "compileSdkVersionCodename='16'\n")
        signing = f"V2 Signer: certificate SHA-256 digest: {certificate}\n"
        with patch.object(apks.subprocess, "run", side_effect=[Mock(stdout=badging), Mock(stdout=signing)]):
            report = apks.verify_apk(self.source / "app-universal-release.apk", "universal",
                                     ("1.4.0", 24), certificate,
                                     aapt2="aapt2 fixture", apksigner="apksigner fixture")
        self.assertEqual(report["certificateSha256"], certificate)

    def test_unrelated_codename_must_not_disguise_a_wrong_package(self):
        badging = ("package: name='other.app' versionCode='24' versionName='1.4.0' "
                   f"compileSdkVersionCodename='{apks.PACKAGE}'\n")
        with patch.object(apks.subprocess, "run", return_value=Mock(stdout=badging)) as run:
            with self.assertRaisesRegex(ValueError, "other.app"):
                apks.verify_apk(self.source / "app-universal-release.apk", "universal",
                                ("1.4.0", 24), "a" * 64,
                                aapt2="aapt2 fixture", apksigner="apksigner fixture")
        run.assert_called_once()

    def test_native_configuration_preserves_update_identity_and_runtime_names(self):
        properties = (TOOL / "android/gradle.properties").read_text()
        self.assertIn("force-version-code-ignoring-abi=true", properties)
        self.assertIn("org.gradle.caching=true", properties)
        self.assertIn("org.gradle.workers.max=2", properties)
        gradle = (TOOL / "android/app.build.gradle.kts").read_text()
        self.assertIn("isUniversalApk = true", gradle)
        self.assertIn('excludes += "lib/x86/**"', gradle)
        self.assertIn("isMinifyEnabled = false", gradle)
        self.assertIn("isShrinkResources = false", gradle)
        certificate = (TOOL / "android/release-certificate.sha256").read_text().strip()
        self.assertRegex(certificate, r"^[a-f0-9]{64}$")

    def test_ci_keeps_four_downloads_and_all_quality_gates(self):
        workflow = (TOOL.parent / ".github/workflows/ci.yml").read_text()
        self.assertEqual(workflow.count("android_apks.py build"), 1)
        self.assertIn("flutter analyze --no-pub", workflow)
        self.assertIn("flutter test --no-pub", workflow)
        self.assertIn("android_apks.py verify", workflow)
        self.assertIn("cache: gradle", workflow)
        for label in apks.APK_FILES:
            artifact = "best-release-apk" + ("" if label == "universal" else "-" + label)
            self.assertIn(f"name: {artifact}\n", workflow)

    def test_smoke_reuses_only_successful_ci_for_the_exact_commit(self):
        workflow = (TOOL.parent / ".github/workflows/android-smoke.yml").read_text()
        self.assertIn('--commit "$GITHUB_SHA" --status success', workflow)
        self.assertIn("actions/download-artifact@v4", workflow)
        self.assertIn("--universal-only", workflow)
        self.assertIn("steps.download-ci-apk.outcome != 'success'", workflow)
        self.assertIn("Extension runtime JVM compatibility tests", workflow)


if __name__ == "__main__":
    unittest.main()
