#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/clipboard-image-tests
xcrun swiftc -parse-as-library Sapphire/Reconstruction/ClipboardImageOptimization.swift Tests/ClipboardImageOptimization/main.swift -o build/clipboard-image-tests/checks
build/clipboard-image-tests/checks
