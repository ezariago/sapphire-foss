#!/bin/bash
set -euo pipefail
SAPPHIRE_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SAPPHIRE_TEST_ROOT"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/phone-tests
java Tests/PhoneReconstruction/AndroidCryptoFixture.java > build/phone-tests/android-crypto.json
xcrun swiftc Sapphire/Reconstruction/PhoneWire.swift Sapphire/Reconstruction/PhoneNotifications.swift Sapphire/Reconstruction/PhoneActionDraft.swift Tests/PhoneReconstruction/main.swift \
    -o build/phone-tests/phone-wire-tests
build/phone-tests/phone-wire-tests build/phone-tests/android-crypto.json
