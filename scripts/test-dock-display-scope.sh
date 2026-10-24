#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/dock-display-tests
xcrun swiftc Sapphire/Reconstruction/DockDisplayScopePolicy.swift Tests/DockDisplayScope/main.swift -o build/dock-display-tests/checks
build/dock-display-tests/checks
xcrun swiftc -parse-as-library Sapphire/Reconstruction/DockDisplayScopePolicy.swift Sapphire/Reconstruction/DockDisplayScope.swift Sapphire/System/Display/Extensions/NSScreen+Extension.swift Tests/DockDisplayScope/NativeReadback.swift -o build/dock-display-tests/native-readback
build/dock-display-tests/native-readback
