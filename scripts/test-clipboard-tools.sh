#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/clipboard-tests
xcrun swiftc Sapphire/Reconstruction/ClipboardToolsPolicy.swift Tests/ClipboardTools/main.swift -o build/clipboard-tests/checks
build/clipboard-tests/checks
