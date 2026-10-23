#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/hover-focus-tests
xcrun swiftc Sapphire/Reconstruction/HoverFocusPolicy.swift Tests/HoverFocus/main.swift -o build/hover-focus-tests/checks
build/hover-focus-tests/checks
