#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/media-tests
xcrun swiftc Sapphire/Reconstruction/NativeMediaProcessor.swift Sapphire/Reconstruction/QuarantineAttribute.swift Tests/MediaTools/main.swift -o build/media-tests/checks
build/media-tests/checks
xcrun swiftc -parse-as-library Sapphire/Reconstruction/NativeMediaProcessor.swift Sapphire/Reconstruction/QuarantineAttribute.swift Tests/MediaTools/Video.swift -o build/media-tests/video
build/media-tests/video
