#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/storage-tests
SAPPHIRE_STORAGE_TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-storage-build.XXXXXX")"
SAPPHIRE_STORAGE_TEST_DATA="$(mktemp -d "$HOME/Library/Caches/sapphire-storage-fixture.XXXXXX")"
SAPPHIRE_STORAGE_TEST_ID="dev.sapphire.storage-fixture.$(uuidgen | tr '[:upper:]' '[:lower:]')"
cleanup() {
    defaults delete "$SAPPHIRE_STORAGE_TEST_ID" >/dev/null 2>&1 || true
    rm -rf "$SAPPHIRE_STORAGE_TEST_ROOT" "$SAPPHIRE_STORAGE_TEST_DATA"
}
trap cleanup EXIT
mkdir -p "$SAPPHIRE_STORAGE_TEST_ROOT/Fixture.app/Contents/MacOS"
python3 - "$SAPPHIRE_STORAGE_TEST_ROOT" "$SAPPHIRE_STORAGE_TEST_ID" <<'PY'
import pathlib, plistlib, sys
with (pathlib.Path(sys.argv[1]) / 'Fixture.app/Contents/Info.plist').open('wb') as file:
    plistlib.dump({'CFBundleIdentifier': sys.argv[2], 'CFBundleExecutable': 'Fixture', 'CFBundlePackageType': 'APPL'}, file)
PY
xcrun swiftc -parse-as-library -D SAPPHIRE_STORAGE_FIXTURE 'Sapphire/App Settings/AppStorageModels.swift' Sapphire/Reconstruction/StorageViews.swift Sapphire/Reconstruction/StorageTreemapLayout.swift Sapphire/Reconstruction/StorageSpaceMap.swift Sapphire/Reconstruction/StorageSpaceMapView.swift Sapphire/Reconstruction/StorageScanHistoryView.swift Tests/Storage/SpaceMapChecks.swift Tests/Storage/support.swift Tests/Storage/main.swift -o "$SAPPHIRE_STORAGE_TEST_ROOT/Fixture.app/Contents/MacOS/Fixture"
codesign --force --sign - "$SAPPHIRE_STORAGE_TEST_ROOT/Fixture.app"
"$SAPPHIRE_STORAGE_TEST_ROOT/Fixture.app/Contents/MacOS/Fixture" "$SAPPHIRE_STORAGE_TEST_DATA" "$PWD/build/storage-tests/workspace.png" "$@"
