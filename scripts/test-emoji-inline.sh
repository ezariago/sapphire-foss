#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/emoji-inline-tests
xcrun swiftc -parse-as-library Sapphire/Reconstruction/SnippetExpansionPolicy.swift Sapphire/Reconstruction/EmojiInlinePolicy.swift Tests/EmojiInline/main.swift -o build/emoji-inline-tests/checks
build/emoji-inline-tests/checks
xcrun swiftc -parse-as-library Sapphire/Reconstruction/SnippetExpansionPolicy.swift Sapphire/Reconstruction/EmojiInlinePolicy.swift Sapphire/Reconstruction/EmojiInlineAX.swift Sapphire/Reconstruction/EmojiInlineSuggestions.swift Tests/EmojiInline/NativeLifecycle.swift -o build/emoji-inline-tests/native
build/emoji-inline-tests/native
