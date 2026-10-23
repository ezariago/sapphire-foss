#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SAPPHIRE_DMG_TEST="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-dmg.XXXXXX")"
cleanup_fixture_mounts() {
    python3 - "$SAPPHIRE_DMG_TEST/Fixture.dmg" <<'PY_CLEANUP'
import os, plistlib, re, subprocess, sys
image = os.path.realpath(sys.argv[1])
result = subprocess.run(['/usr/bin/hdiutil', 'info', '-plist'], capture_output=True, timeout=30)
if result.returncode:
    sys.exit(1)
for mounted in plistlib.loads(result.stdout).get('images', []):
    if os.path.realpath(mounted.get('image-path', '')) != image:
        continue
    devices = [entry.get('dev-entry', '') for entry in mounted.get('system-entities', [])]
    device = next((entry for entry in devices if re.fullmatch(r'/dev/disk[0-9]+', entry)), None)
    if not device:
        sys.exit('Could not identify the test fixture device for cleanup.')
    result = subprocess.run(['/usr/bin/hdiutil', 'detach', device], capture_output=True, timeout=30)
    if result.returncode:
        sys.exit('Fixture detach failed; retaining temporary fixture files.')
PY_CLEANUP
}
cleanup_fixture() {
    if cleanup_fixture_mounts; then rm -rf "$SAPPHIRE_DMG_TEST"; fi
}
trap cleanup_fixture EXIT
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
for SAPPHIRE_MOUNT_ATTEMPT in 1 2 3; do
    if build/dmg-tests/checks "$SAPPHIRE_DMG_TEST"; then exit 0; else SAPPHIRE_FIXTURE_STATUS=$?; fi
    # Retry only the classified transient attach failure, never an install/assertion failure.
    if [[ "$SAPPHIRE_FIXTURE_STATUS" != 75 || "$SAPPHIRE_MOUNT_ATTEMPT" == 3 ]]; then exit "$SAPPHIRE_FIXTURE_STATUS"; fi
    cleanup_fixture_mounts
    sleep "$SAPPHIRE_MOUNT_ATTEMPT"
done
