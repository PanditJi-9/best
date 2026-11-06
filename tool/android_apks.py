#!/usr/bin/env python3
"""Build four standalone APKs once and verify their ABI/update identities.

ZIP/ELF checks and APK signatures are packaging evidence, not Android launch,
image-decoding or playback evidence. No APK is unpacked, rewritten or re-signed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "apps/best_app"
PACKAGE = "app.best.best_app"
APK_FILES = {
    "arm64-v8a": "app-arm64-v8a-release.apk",
    "armeabi-v7a": "app-armeabi-v7a-release.apk",
    "x86_64": "app-x86_64-release.apk",
    "universal": "app-release.apk",
}
ELF_ABIS = {"arm64-v8a": (2, 183), "armeabi-v7a": (1, 40), "x86_64": (2, 62)}


def package_version(app: Path) -> tuple[str, int]:
    match = re.search(r"^version:[ \t]*([^\s#]+)",
                      (app / "pubspec.yaml").read_text(), re.MULTILINE)
    if match is None:
        raise ValueError("pubspec.yaml has no application version")
    version = match.group(1).strip("\"'")
    parsed = re.fullmatch(r"(\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?)\+(\d+)", version)
    if parsed is None or not 0 < int(parsed.group(2)) <= 2100000000:
        raise ValueError("Use an explicit valid Android build number in pubspec.yaml")
    return parsed.group(1), int(parsed.group(2))


def apk_contents(apk: Path, label: str) -> dict:
    expected = set(ELF_ABIS) if label == "universal" else {label}
    if not expected <= ELF_ABIS.keys():
        raise ValueError(f"Unsupported APK architecture: {label}")
    with zipfile.ZipFile(apk) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)):
            raise ValueError(f"{apk.name}: duplicate archive entries")
        if not {"AndroidManifest.xml", "classes.dex"} <= set(names):
            raise ValueError(f"{apk.name}: not a standalone application APK")
        if not any(name.startswith("assets/flutter_assets/") for name in names):
            raise ValueError(f"{apk.name}: Flutter assets are missing")
        libraries = [entry for entry in entries
                     if re.fullmatch(r"lib/[^/]+/[^/]+\.so", entry.filename)]
        found = {entry.filename.split("/")[1] for entry in libraries}
        if found != expected:
            raise ValueError(f"{apk.name}: expected ABIs {sorted(expected)}, found {sorted(found)}")
        for abi in expected:
            for library in ("libflutter.so", "libapp.so"):
                if f"lib/{abi}/{library}" not in names:
                    raise ValueError(f"{apk.name}: {abi}/{library} is missing")
        for entry in libraries:
            abi = entry.filename.split("/")[1]
            with archive.open(entry) as library:
                header = library.read(20)
            elf_class, machine = ELF_ABIS[abi]
            if (len(header) < 20 or header[:4] != b"\x7fELF"
                    or header[4] != elf_class or header[5] != 1
                    or int.from_bytes(header[18:20], "little") != machine):
                raise ValueError(f"{apk.name}: wrong native architecture in {entry.filename}")
    with apk.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    return {"file": APK_FILES[label], "abis": sorted(found),
            "bytes": apk.stat().st_size, "sha256": digest}


def collect_apks(app: Path) -> dict:
    version_name, version_code = package_version(app)
    source = app / "build/app/outputs/apk/release"
    metadata = json.loads((source / "output-metadata.json").read_text())
    if metadata.get("applicationId") != PACKAGE or metadata.get("variantName") != "release":
        raise ValueError("APK metadata is not for Best's release variant")
    outputs = {}
    for element in metadata.get("elements", []):
        filters = element.get("filters", [])
        if not filters:
            label = "universal"
        elif len(filters) == 1 and filters[0].get("filterType") == "ABI":
            label = filters[0].get("value")
        else:
            raise ValueError("Expected standalone ABI APKs, not additional install splits")
        if label not in APK_FILES or label in outputs:
            raise ValueError(f"Unexpected or duplicate APK output: {label}")
        if element.get("versionName") != version_name or element.get("versionCode") != version_code:
            raise ValueError("All four APKs must share pubspec's version name and build number")
        filename = element.get("outputFile", "")
        if (not isinstance(filename, str) or not filename
                or Path(filename).name != filename or not filename.endswith(".apk")):
            raise ValueError("APK metadata contains an unsafe output filename")
        outputs[label] = source / filename
    if set(outputs) != APK_FILES.keys():
        raise ValueError("Expected ARM64, ARM32, x86_64 and Universal from the same build")

    # Validate current AGP outputs before copying. An old app-release.apk in
    # flutter-apk must not masquerade as a freshly built universal output.
    files = {label: apk_contents(outputs[label], label) for label in APK_FILES}
    destination = app / "build/release-apks"
    destination.mkdir(parents=True, exist_ok=True)
    for label, filename in APK_FILES.items():
        shutil.copyfile(outputs[label], destination / filename)
    manifest = {"package": PACKAGE, "versionName": version_name,
                "versionCode": version_code, "apks": files}
    (destination / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (destination / "SHA256SUMS").write_text("".join(
        f"{details['sha256']}  {details['file']}\n" for details in files.values()))
    return manifest


def build_apks(app: Path = APP, flutter: str | None = None) -> dict:
    started = time.monotonic()
    subprocess.run([
        flutter or os.environ.get("FLUTTER", "flutter"), "build", "apk", "--release",
        "--no-pub", "--split-per-abi", "--target-platform", "android-arm,android-arm64,android-x64",
    ], cwd=app, check=True)
    manifest = collect_apks(app)
    manifest["buildSeconds"] = round(time.monotonic() - started, 1)
    return manifest


def android_tool(name: str) -> str:
    sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    paths = list(Path(sdk).glob(f"build-tools/*/{name}")) if sdk else []
    paths = [path for path in paths if path.is_file()]
    if paths:
        return str(max(paths, key=lambda path: tuple(map(int, re.findall(r"\d+", path.parent.name)))))
    executable = shutil.which(name)
    if executable is None:
        raise ValueError(f"Android SDK tool {name} was not found")
    return executable


def verify_apk(apk: Path, label: str, version: tuple[str, int],
               certificate: str, *, aapt2: str, apksigner: str) -> dict:
    details = apk_contents(apk, label)
    badging = subprocess.run([aapt2, "dump", "badging", str(apk)],
                             check=True, capture_output=True, text=True).stdout
    package_line = next((line for line in badging.splitlines() if line.startswith("package: ")), "")
    identity = dict(re.findall(r"(name|versionCode|versionName)='([^']*)'", package_line))
    if identity != {"name": PACKAGE, "versionName": version[0], "versionCode": str(version[1])}:
        raise ValueError(f"{apk.name}: package/version identity does not match this build")
    signed = subprocess.run([apksigner, "verify", "--print-certs", str(apk)],
                            check=True, capture_output=True, text=True).stdout
    fingerprints = re.findall(
        r"(?:Signer #\d+|V\d(?:\.\d)? Signer):? certificate SHA-256 digest:\s*([a-fA-F0-9]{64})",
        signed)
    if {fingerprint.lower() for fingerprint in fingerprints} != {certificate.lower()}:
        raise ValueError(f"{apk.name}: not signed with the established Best release certificate")
    details["certificateSha256"] = certificate.lower()
    return details


def verify_apks(directory: Path, *, universal_only: bool = False,
                app: Path = APP) -> dict:
    version = package_version(app)
    certificate = (ROOT / "tool/android/release-certificate.sha256").read_text().strip()
    aapt2, apksigner = android_tool("aapt2"), android_tool("apksigner")
    labels = ["universal"] if universal_only else APK_FILES
    verified = {label: verify_apk(directory / APK_FILES[label], label, version,
                                  certificate, aapt2=aapt2, apksigner=apksigner)
                for label in labels}
    report = {"package": PACKAGE, "versionName": version[0],
              "versionCode": version[1], "apks": verified}
    (directory / "signatures.json").write_text(json.dumps(report, indent=2) + "\n")
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "verify"))
    parser.add_argument("--directory", type=Path, default=APP / "build/release-apks")
    parser.add_argument("--universal-only", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "build":
            if args.universal_only or args.directory != APP / "build/release-apks":
                parser.error("Build always produces the four APKs in build/release-apks")
            report = build_apks()
        else:
            report = verify_apks(args.directory, universal_only=args.universal_only)
        print(json.dumps(report, indent=2))
        return 0
    except (ValueError, OSError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f"APK packaging failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
