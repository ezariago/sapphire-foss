#!/bin/bash
set -euo pipefail
SAPPHIRE_COMPANION_ROOT="$(cd "$(dirname "$0")" && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [[ -z "${JAVA_HOME:-}" && -x /usr/libexec/java_home ]]; then
    export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
fi
cd "$SAPPHIRE_COMPANION_ROOT"
./gradlew --console=plain :app:testDebugUnitTest :app:assembleDebug :helper:assembleDebug
mkdir -p build/apks
cp app/build/outputs/apk/debug/app-debug.apk build/apks/SapphireCompanion.apk
cp helper/build/outputs/apk/debug/helper-debug.apk build/apks/SapphireHotspotHelper.apk
printf 'Built APKs in %s/build/apks/\n' "$SAPPHIRE_COMPANION_ROOT"
