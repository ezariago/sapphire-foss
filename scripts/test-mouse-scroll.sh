#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/mouse-scroll-tests
xcrun swiftc Sapphire/Reconstruction/MouseScrollPolicy.swift Sapphire/Reconstruction/MouseScrollEventTransform.swift Tests/MouseScroll/main.swift -o build/mouse-scroll-tests/checks
build/mouse-scroll-tests/checks
