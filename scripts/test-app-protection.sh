#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SAPPHIRE_SHIELD_TEST="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-shield.XXXXXX")"
trap 'rm -rf "$SAPPHIRE_SHIELD_TEST"' EXIT
mkdir -p "$SAPPHIRE_SHIELD_TEST/Fixture.app/Contents/MacOS" build/app-protection-tests
xcrun swiftc Tests/AppProtection/fixture.swift -o "$SAPPHIRE_SHIELD_TEST/Fixture.app/Contents/MacOS/Fixture"
python3 - "$SAPPHIRE_SHIELD_TEST" <<'PY'
import pathlib, plistlib, sys
with (pathlib.Path(sys.argv[1]) / 'Fixture.app/Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'dev.sapphire.shield-fixture', 'CFBundleExecutable': 'Fixture', 'CFBundlePackageType': 'APPL'}, f)
PY
codesign --force --sign - "$SAPPHIRE_SHIELD_TEST/Fixture.app"
xcrun swiftc Sapphire/Stubs/AppProtectionCore.swift Tests/AppProtection/main.swift -o build/app-protection-tests/checks
build/app-protection-tests/checks "$SAPPHIRE_SHIELD_TEST/Fixture.app" "$@"
