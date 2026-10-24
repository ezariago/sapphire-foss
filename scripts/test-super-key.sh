#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/super-key-tests
xcrun swiftc Sapphire/Reconstruction/SuperKeyPolicy.swift Sapphire/Reconstruction/MouseScrollPolicy.swift Sapphire/Reconstruction/MouseScrollEventTransform.swift Tests/SuperKey/main.swift -o build/super-key-tests/checks
build/super-key-tests/checks
