#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/snippet-tests
xcrun swiftc Sapphire/Reconstruction/SnippetExpansionPolicy.swift Tests/Snippets/main.swift -o build/snippet-tests/checks
build/snippet-tests/checks
