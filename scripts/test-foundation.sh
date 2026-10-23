#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SAPPHIRE_FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/sapphire-security.XXXXXX")"
trap 'rm -rf "$SAPPHIRE_FIXTURES"' EXIT
python3 - "$SAPPHIRE_FIXTURES" <<'PY'
import pathlib, plistlib, shutil, subprocess, sys
root = pathlib.Path(sys.argv[1])
for name in ['Original', 'Changed', 'WrongID', 'Unsigned']:
    contents = root / f'{name}.app' / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Resources').mkdir()
    shutil.copy('/usr/bin/true', contents / 'MacOS' / 'Fixture')
    with (contents / 'Info.plist').open('wb') as f:
        plistlib.dump({'CFBundleIdentifier': 'dev.sapphire.wrong' if name == 'WrongID' else 'dev.sapphire.security-fixture', 'CFBundleExecutable': 'Fixture', 'CFBundlePackageType': 'APPL'}, f)
    (contents / 'Resources' / 'data.txt').write_text(name)
    subprocess.run(['codesign', '--remove-signature', str(contents / 'MacOS' / 'Fixture')], check=True)
    if name != 'Unsigned':
        subprocess.run(['codesign', '--force', '--sign', '-', str(contents.parent)], check=True)
shutil.copytree(root / 'Original.app', root / 'Identical.app')
shutil.copytree(root / 'Original.app', root / 'Tampered.app')
(root / 'Tampered.app' / 'Contents' / 'Resources' / 'data.txt').write_text('tampered')
PY
mkdir -p build/foundation-tests
xcrun swiftc Sapphire/Stubs/AppSecurity.swift Sapphire/Stubs/SubscriptionCore.swift Tests/Foundation/main.swift -o build/foundation-tests/checks
build/foundation-tests/checks "$SAPPHIRE_FIXTURES"
