#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SAPPHIRE_DMG_TEST="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-dmg.XXXXXX")"
trap 'rm -rf "$SAPPHIRE_DMG_TEST"' EXIT
mkdir -p "$SAPPHIRE_DMG_TEST/Source/Fixture.app/Contents/MacOS" "$SAPPHIRE_DMG_TEST/Source/Fixture.app/Contents/Resources" build/dmg-tests
cp /usr/bin/true "$SAPPHIRE_DMG_TEST/Source/Fixture.app/Contents/MacOS/Fixture"
python3 - "$SAPPHIRE_DMG_TEST" <<'PY'
import pathlib, plistlib, sys
contents = pathlib.Path(sys.argv[1]) / 'Source/Fixture.app/Contents'
with (contents / 'Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'dev.sapphire.install-fixture', 'CFBundleExecutable': 'Fixture', 'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0'}, f)
(contents / 'Resources/fixture.txt').write_text('fixture')
PY
codesign --force --sign - "$SAPPHIRE_DMG_TEST/Source/Fixture.app"
hdiutil create -quiet -srcfolder "$SAPPHIRE_DMG_TEST/Source" -volname SapphireFixture -format UDZO "$SAPPHIRE_DMG_TEST/Fixture.dmg"
xcrun swiftc Sapphire/Stubs/AppSecurity.swift Sapphire/Reconstruction/QuarantineAttribute.swift Sapphire/Reconstruction/DiskImageInstaller.swift Tests/DMGInstaller/main.swift -o build/dmg-tests/checks
build/dmg-tests/checks "$SAPPHIRE_DMG_TEST"
