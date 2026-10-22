#!/bin/bash
set -euo pipefail
SAPPHIRE_MAC_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SAPPHIRE_ANDROID_SOURCE="${SAPPHIRE_ANDROID_SOURCE:-$SAPPHIRE_MAC_ROOT/../sapphire-android-companion}"
if [[ ! -f "$SAPPHIRE_ANDROID_SOURCE/scripts/test-android-companion-device.sh" ]]; then
    echo 'Clone https://github.com/ezariago/sapphire-android-companion beside the Mac checkout, or set SAPPHIRE_ANDROID_SOURCE.' >&2
    exit 1
fi
exec "$SAPPHIRE_ANDROID_SOURCE/scripts/test-android-companion-device.sh" "$@"
