#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/keyboard-bounce-tests
xcrun swiftc Sapphire/Reconstruction/KeyboardBouncePolicy.swift Tests/KeyboardBounce/main.swift -o build/keyboard-bounce-tests/checks
build/keyboard-bounce-tests/checks
