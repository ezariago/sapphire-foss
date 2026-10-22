#!/bin/bash
set -euo pipefail
SAPPHIRE_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
if [[ -z "${JAVA_HOME:-}" ]]; then export JAVA_HOME="$(/usr/libexec/java_home -v 17)"; fi
SAPPHIRE_HOTSPOT_TEST=false
if [[ "${1:-}" == --hotspot ]]; then SAPPHIRE_HOTSPOT_TEST=true
elif [[ $# != 0 ]]; then echo 'Usage: test-android-companion-device.sh [--hotspot]' >&2; exit 2; fi
cd "$SAPPHIRE_TEST_ROOT/AndroidCompanion"
./gradlew --console=plain :app:assembleDebugAndroidTest
adb install --user 0 -r app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk
SAPPHIRE_DEVICE_RESULT="$(adb shell am instrument --user 0 -w -e hotspot "$SAPPHIRE_HOTSPOT_TEST" dev.sapphire.companion.test/dev.sapphire.companion.DeviceChecks)"
printf '%s\n' "$SAPPHIRE_DEVICE_RESULT"
if [[ "$SAPPHIRE_DEVICE_RESULT" != *'INSTRUMENTATION_RESULT: result=passed'* ]]; then exit 1; fi
if [[ "$SAPPHIRE_HOTSPOT_TEST" == true && "$SAPPHIRE_DEVICE_RESULT" != *'INSTRUMENTATION_RESULT: hotspotStarted=true'* ]]; then exit 1; fi
if [[ "$SAPPHIRE_HOTSPOT_TEST" == true && "$SAPPHIRE_DEVICE_RESULT" != *'INSTRUMENTATION_RESULT: hotspotStopState=stopped'* ]]; then exit 1; fi
