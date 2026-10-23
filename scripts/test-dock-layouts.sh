#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/dock-tests
xcrun swiftc Sapphire/Reconstruction/DockLayout.swift Tests/DockLayouts/main.swift -o build/dock-tests/checks
build/dock-tests/checks
