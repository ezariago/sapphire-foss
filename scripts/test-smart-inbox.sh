#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/smart-inbox-tests
xcrun swiftc -parse-as-library Sapphire/Stubs/SmartInboxFeatures.swift Sapphire/Stubs/VerificationCodeDetector.swift Sapphire/Reconstruction/SmartInboxPolicy.swift Sapphire/Reconstruction/SmartInboxMonitor.swift Tests/SmartInbox/support.swift Tests/SmartInbox/main.swift -o build/smart-inbox-tests/checks
build/smart-inbox-tests/checks
