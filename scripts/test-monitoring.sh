#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/monitoring-tests
xcrun swiftc Sapphire/Services/Stats/StatsMath.swift Sapphire/Reconstruction/MonitoringDeliveryPolicy.swift Tests/Monitoring/main.swift -o build/monitoring-tests/checks
build/monitoring-tests/checks
