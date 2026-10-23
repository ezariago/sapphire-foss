#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/window-cycling-tests
xcrun swiftc Sapphire/Reconstruction/WindowCyclePolicy.swift Sapphire/Reconstruction/WindowSwitcherKeyPolicy.swift Tests/WindowCycling/main.swift -o build/window-cycling-tests/checks
build/window-cycling-tests/checks
