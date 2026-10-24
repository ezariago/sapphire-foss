#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/region-text-search-tests
xcrun swiftc -parse-as-library Sapphire/Reconstruction/RegionTextSearchSession.swift Tests/RegionTextSearch/main.swift -o build/region-text-search-tests/checks
build/region-text-search-tests/checks
xcrun swiftc -parse-as-library Sapphire/Reconstruction/RegionTextSearchSession.swift Sapphire/Reconstruction/RegionTextCapture.swift Sapphire/Reconstruction/NativeMediaProcessor.swift Sapphire/Reconstruction/QuarantineAttribute.swift Sapphire/Stubs/CircleToSearchManager.swift Sapphire/Stubs/CircleToSearchResultsView.swift Tests/RegionTextSearch/NativeLifecycle.swift -o build/region-text-search-tests/native-lifecycle
build/region-text-search-tests/native-lifecycle
