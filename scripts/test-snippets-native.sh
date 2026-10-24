#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SAPPHIRE_SNIPPET_FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-snippet.XXXXXX")"
trap 'rm -rf "$SAPPHIRE_SNIPPET_FIXTURE"' EXIT
mkdir -p "$SAPPHIRE_SNIPPET_FIXTURE/Fixture.app/Contents/MacOS" build/snippet-tests
xcrun swiftc Tests/Snippets/fixture.swift -o "$SAPPHIRE_SNIPPET_FIXTURE/Fixture.app/Contents/MacOS/Fixture"
python3 - "$SAPPHIRE_SNIPPET_FIXTURE" <<'PY'
import pathlib, plistlib, sys
with (pathlib.Path(sys.argv[1]) / 'Fixture.app/Contents/Info.plist').open('wb') as file:
    plistlib.dump({'CFBundleIdentifier': 'dev.sapphire.snippet-fixture', 'CFBundleExecutable': 'Fixture', 'CFBundlePackageType': 'APPL'}, file)
PY
codesign --force --sign - "$SAPPHIRE_SNIPPET_FIXTURE/Fixture.app"
cp Tests/Snippets/native.swift "$SAPPHIRE_SNIPPET_FIXTURE/main.swift"
xcrun swiftc Sapphire/Reconstruction/SnippetExpansionPolicy.swift "$SAPPHIRE_SNIPPET_FIXTURE/main.swift" -o build/snippet-tests/native-checks
build/snippet-tests/native-checks "$SAPPHIRE_SNIPPET_FIXTURE/Fixture.app"
