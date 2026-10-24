#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/shortcut-dispatcher-tests
xcrun swiftc -parse-as-library Sapphire/Models/SnapZoneModels.swift Sapphire/Services/Zones/KeyboardShortcutManager.swift Tests/ShortcutDispatcher/support.swift Tests/ShortcutDispatcher/main.swift -o build/shortcut-dispatcher-tests/checks
build/shortcut-dispatcher-tests/checks
