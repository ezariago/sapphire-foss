#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
mkdir -p build/power-telemetry-tests
xcrun swiftc Sapphire/Reconstruction/PowerTelemetry.swift Tests/PowerTelemetry/main.swift -o build/power-telemetry-tests/checks
build/power-telemetry-tests/checks
xcrun swiftc -parse-as-library Sapphire/Reconstruction/PowerTelemetry.swift Sapphire/Models/BatteryStatsViewModel.swift Tests/PowerTelemetry/support.swift Tests/PowerTelemetry/model.swift -o build/power-telemetry-tests/model-checks
build/power-telemetry-tests/model-checks
