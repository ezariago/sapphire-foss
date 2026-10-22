#!/bin/bash
set -euo pipefail
SAPPHIRE_ANDROID_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$SAPPHIRE_ANDROID_ROOT/AndroidCompanion/build.sh"
mkdir -p "$SAPPHIRE_ANDROID_ROOT/build/android"
cp "$SAPPHIRE_ANDROID_ROOT/AndroidCompanion/build/apks/SapphireCompanion.apk" "$SAPPHIRE_ANDROID_ROOT/build/android/SapphireCompanion.apk"
cp "$SAPPHIRE_ANDROID_ROOT/AndroidCompanion/build/apks/SapphireHotspotHelper.apk" "$SAPPHIRE_ANDROID_ROOT/build/android/SapphireHotspotHelper.apk"
printf 'APKs: %s/build/android/\n' "$SAPPHIRE_ANDROID_ROOT"
