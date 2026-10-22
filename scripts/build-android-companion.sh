#!/bin/bash
set -euo pipefail
SAPPHIRE_ANDROID_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAPPHIRE_ANDROID_SOURCE="${SAPPHIRE_ANDROID_SOURCE:-$SAPPHIRE_ANDROID_ROOT/../sapphire-android-companion}"
if [[ ! -f "$SAPPHIRE_ANDROID_SOURCE/build.sh" ]]; then
    echo 'Clone https://github.com/ezariago/sapphire-android-companion beside the Mac checkout, or set SAPPHIRE_ANDROID_SOURCE.' >&2
    exit 1
fi
"$SAPPHIRE_ANDROID_SOURCE/build.sh"
mkdir -p "$SAPPHIRE_ANDROID_ROOT/build/android"
cp "$SAPPHIRE_ANDROID_SOURCE/build/apks/SapphireCompanion.apk" "$SAPPHIRE_ANDROID_ROOT/build/android/SapphireCompanion.apk"
cp "$SAPPHIRE_ANDROID_SOURCE/build/apks/SapphireHotspotHelper.apk" "$SAPPHIRE_ANDROID_ROOT/build/android/SapphireHotspotHelper.apk"
printf 'APKs: %s/build/android/\n' "$SAPPHIRE_ANDROID_ROOT"
