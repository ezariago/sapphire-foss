#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/selection-services-tests
xcrun swiftc -parse-as-library Sapphire/Services/System/PlainTextSanitizer.swift Sapphire/Reconstruction/ClipboardToolsPolicy.swift Sapphire/Reconstruction/ContextMenuServices.swift Tests/SelectionServices/support.swift Tests/SelectionServices/main.swift -o build/selection-services-tests/checks
build/selection-services-tests/checks
