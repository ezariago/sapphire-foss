#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/mouse-button-tests
xcrun swiftc -parse-as-library Sapphire/Reconstruction/MouseButtonRemapPolicy.swift Sapphire/Reconstruction/MouseButtonEventAdapter.swift Sapphire/Reconstruction/MouseMenuDelivery.swift Tests/MouseButtons/main.swift -o build/mouse-button-tests/checks
build/mouse-button-tests/checks
xcrun swiftc -parse-as-library Sapphire/Reconstruction/MouseButtonRemapPolicy.swift Sapphire/Reconstruction/MouseButtonEventAdapter.swift Sapphire/Reconstruction/MouseMenuDelivery.swift Sapphire/Reconstruction/MouseButtonRemapManager.swift Sapphire/Reconstruction/MouseSystemActions.swift Tests/MouseButtons/NativeLifecycle.swift -o build/mouse-button-tests/native-lifecycle
build/mouse-button-tests/native-lifecycle
