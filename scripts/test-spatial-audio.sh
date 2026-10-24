#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/spatial-audio-tests
xcrun swiftc Sapphire/Reconstruction/SpatialAudioSettings.swift Tests/SpatialAudio/main.swift -o build/spatial-audio-tests/checks
build/spatial-audio-tests/checks
