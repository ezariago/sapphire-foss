#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/hinge-animation-tests
xcrun swiftc -parse-as-library Sapphire/Reconstruction/HingeAnimationPolicy.swift Sapphire/Reconstruction/HingeAnimationEngine.swift Tests/HingeAnimation/main.swift -o build/hinge-animation-tests/checks
build/hinge-animation-tests/checks
xcrun swiftc -parse-as-library Sapphire/Reconstruction/HingeAnimationPolicy.swift Sapphire/Reconstruction/HingeAnimationEngine.swift Sapphire/Reconstruction/HingeAnimationManager.swift Sapphire/System/Display/Extensions/NSScreen+Extension.swift Tests/HingeAnimation/NativeLifecycle.swift -o build/hinge-animation-tests/native-lifecycle
build/hinge-animation-tests/native-lifecycle
