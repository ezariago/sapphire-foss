#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
fixture="build/emoji-inline-native/EmojiFixture.app"
mkdir -p "$fixture/Contents/MacOS" build/emoji-inline-native/driver
xcrun swiftc Tests/EmojiInline/fixture.swift -o "$fixture/Contents/MacOS/EmojiFixture"
python3 - <<'PY'
import plistlib
from pathlib import Path
Path('build/emoji-inline-native/EmojiFixture.app/Contents/Info.plist').write_bytes(plistlib.dumps({
 'CFBundleIdentifier':'dev.sapphire.emoji-fixture','CFBundleName':'Sapphire Emoji Fixture',
 'CFBundleExecutable':'EmojiFixture','CFBundlePackageType':'APPL','LSUIElement':True,
 'CFBundleVersion':'1','CFBundleShortVersionString':'1.0','LSMinimumSystemVersion':'12.0'}))
PY
codesign --force --sign - "$fixture" >/dev/null
cp Tests/EmojiInline/native.swift build/emoji-inline-native/driver/main.swift
xcrun swiftc Sapphire/Reconstruction/SnippetExpansionPolicy.swift Sapphire/Reconstruction/EmojiInlinePolicy.swift Sapphire/Reconstruction/EmojiInlineAX.swift build/emoji-inline-native/driver/main.swift -o build/emoji-inline-native/driver/checks
build/emoji-inline-native/driver/checks "$PWD/$fixture"

build/emoji-inline-native/driver/checks "$PWD/$fixture" --long-prefix
