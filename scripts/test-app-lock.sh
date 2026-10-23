#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/app-protection-tests
xcrun swiftc Sapphire/Reconstruction/AppLockConfigurationRevision.swift Sapphire/Stubs/AppProtectionCore.swift Sapphire/Stubs/AppLockManager.swift Sapphire/Stubs/AppLockOverlayView.swift Tests/AppProtection/SettingsFixture.swift Tests/AppLock/main.swift -o build/app-protection-tests/auth-checks
build/app-protection-tests/auth-checks
