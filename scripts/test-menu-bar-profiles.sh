#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/menu-bar-profile-tests
xcrun swiftc -parse-as-library Sapphire/Reconstruction/MenuBarProfileModels.swift Sapphire/Reconstruction/MenuBarProfilePolicy.swift Sapphire/Reconstruction/MenuBarProfileEngine.swift Tests/MenuBarProfiles/support.swift Tests/MenuBarProfiles/main.swift -o build/menu-bar-profile-tests/checks
build/menu-bar-profile-tests/checks
