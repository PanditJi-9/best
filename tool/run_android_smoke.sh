#!/bin/sh
# emulator-runner executes each script line in a NEW shell. Run the entire
# session in one file so exit status and the diagnostic trap actually survive.
set -eu

save_logs() {
  adb logcat -d -v brief > logcat.txt || true
  grep -iE 'BestExtensions|extension|injekt|tachiyomi|DexClassLoader|ClassNotFound|NoClassDef' \
    logcat.txt > extensions.log || true
}
trap save_logs EXIT

adb install -r apps/best_app/build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -W -n app.best.best_app/.MainActivity
sleep 25
test -n "$(adb shell pidof app.best.best_app)"

smoke=0
python3 -u tool/extension_probe.py || smoke=$?
python3 -u tool/manga_smoke.py || smoke=$?
python3 -u tool/anime_smoke.py || smoke=$?
python3 -u tool/android_smoke.py || smoke=$?
exit "$smoke"
