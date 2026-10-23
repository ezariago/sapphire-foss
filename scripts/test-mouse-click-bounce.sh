#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/mouse-click-bounce-tests
xcrun swiftc Sapphire/Reconstruction/MouseClickBouncePolicy.swift Tests/MouseClickBounce/main.swift -o build/mouse-click-bounce-tests/checks
build/mouse-click-bounce-tests/checks
