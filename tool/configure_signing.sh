#!/usr/bin/env sh
# Writes the release keystore from CI secrets, when they exist.
#
# The key never lives in the repository or in a build log. Without the secret
# the build falls back to the Android debug key, which is fine for a preview
# APK but cannot be updated in place across CI runs (every runner generates a
# new debug key), so tagged releases are always built with this one.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/apps/best_app"

if [ -z "${ANDROID_KEYSTORE_BASE64:-}" ]; then
  echo "No ANDROID_KEYSTORE_BASE64 in the environment; using the debug key."
  exit 0
fi

printf '%s' "$ANDROID_KEYSTORE_BASE64" | base64 -d > "$APP/android/app/best-release.jks"

cat > "$APP/android/key.properties" <<EOF
storePassword=${ANDROID_KEYSTORE_PASSWORD}
keyPassword=${ANDROID_KEY_PASSWORD}
keyAlias=${ANDROID_KEY_ALIAS}
storeFile=best-release.jks
EOF

chmod 600 "$APP/android/key.properties" "$APP/android/app/best-release.jks"
echo "Release signing configured."
