#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/auto-quit-tests
xcrun swiftc Sapphire/Reconstruction/AutoQuitPolicy.swift Tests/AutoQuit/main.swift -o build/auto-quit-tests/checks
build/auto-quit-tests/checks
