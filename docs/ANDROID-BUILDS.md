# Android APK variants and build time

Best produces four **standalone alternatives**. Install one APK, not all four;
these are not Android configuration splits that need to be installed together.
All variants contain the same features, Arabic/English UI, library and reader.

| Variant | Target | APK | Actions artifact |
| --- | --- | --- | --- |
| ARM64 | 64-bit ARM / `arm64-v8a` | `app-arm64-v8a-release.apk` | `best-release-apk-arm64-v8a` |
| ARM32 | 32-bit ARM / `armeabi-v7a` | `app-armeabi-v7a-release.apk` | `best-release-apk-armeabi-v7a` |
| x86_64 | 64-bit Intel/AMD / `x86_64` | `app-x86_64-release.apk` | `best-release-apk-x86_64` |
| Universal | All three supported ABIs | `app-release.apk` | `best-release-apk` |

`x86` **32-bit Intel is not supported by Flutter release builds**. Native x86
files shipped by dependencies are excluded rather than falsely advertising a
working architecture. Universal is the larger fallback when the device ABI is
unknown; an ABI-specific APK avoids downloading other processors' native code.

## One build, four files

After platform bootstrap, dependency resolution and localization:

```sh
python3 tool/android_apks.py build
```

This runs `flutter build apk --release --no-pub --split-per-abi` once, targeting
ARM32, ARM64 and x86_64. The owned Gradle script enables the additional universal
output in the **same** assembly. Dart AOT, Kotlin/Java and assets are not rebuilt
in a separate universal pass. No APK is unpacked, rewritten or re-signed.

The helper collects the current Gradle `output-metadata.json`, not old files in
`flutter-apk`. It requires all four outputs, the correct package/version, matching
ELF machine types, and both `libflutter.so` and `libapp.so` for each target.
Results go to `apps/best_app/build/release-apks/`, alongside `manifest.json` and
`SHA256SUMS`.

## Safe updates between variants

The four direct-install APKs use the same `app.best.best_app` application ID,
version name, build number and established release certificate. Flutter's
per-ABI version-code offsets are disabled for these downloads: switching back
to Universal must not turn into a downgrade or require uninstalling the library.
Android still rejects an incompatible processor, a genuinely older build or a
different signing key.

CI verifies **each actual APK manifest and signature**, not just filenames or
Gradle metadata, before uploading any variant. The public expected fingerprint
lives in `tool/android/release-certificate.sha256`; the private signing key stays
in Actions secrets. A contributor's local debug-signed build is not a verified
Best release.

This equal-version-code scheme is for direct downloads. For Google Play, use an
Android App Bundle rather than uploading these four APKs as a multi-APK release.

## Build-time savings

- One Flutter/Gradle assembly produces the four APKs, rather than four builds or
  a second universal build.
- Gradle dependencies, wrapper and build-cache outputs persist across CI runs.
  Parallel work remains bounded by the existing two-worker and 3G/2G heap limits.
  Experimental configuration caching is not enabled.
- `flutter pub get` runs once; analyze, tests and APK assembly use `--no-pub`.
- APK artifacts use fast compression (level 1), retaining useful transfer-size
  reduction without the default level-6 compression cost.
- Android smoke reuses a **successful CI universal APK for the exact checked-out
  commit**. It rechecks that APK's ABI, manifest and release signature and still
  runs the real emulator/source/reader/player gates. Only the already-passed
  compile/JVM work is reused. An absent or expired artifact falls back to a fresh
  signed build and JVM tests.

The previous cold universal build (`1a0af00`, CI `42309115302`) spent **414.1 s**
in `assembleRelease`, plus a separate JVM test invocation. The first four-APK run
still has cold Gradle/SDK work; warm-cache savings depend on the changed inputs
and runner. No fixed percentage or per-device runtime performance is claimed.

APK structure, signature and build success do **not** prove installation,
image decoding or video playback on all three device architectures. Emulator
smoke and physical-device checks remain separate release evidence.
