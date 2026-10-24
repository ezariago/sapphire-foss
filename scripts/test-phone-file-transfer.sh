#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/file-transfer-tests
xcrun swiftc Sapphire/Reconstruction/PhoneWire.swift Sapphire/Reconstruction/PhoneFileTransfer.swift Tests/PhoneFileTransfer/main.swift -o build/file-transfer-tests/checks
build/file-transfer-tests/checks build/file-transfer-tests/wire.json
