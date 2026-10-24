#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct SystemPowerReading {
    let systemLoad: Double
    let adapterPower: Double
    let adapterConnected: Bool
    let isCharging: Bool
    let systemAvailable: Bool
    let adapterAvailable: Bool
    let powerSourceAvailable: Bool

    init(systemLoad: Double, adapterPower: Double, adapterConnected: Bool, isCharging: Bool,
         systemAvailable: Bool = true, adapterAvailable: Bool = true, powerSourceAvailable: Bool = true) {
        self.systemLoad = PowerTelemetry.validWatts(systemLoad) ?? 0
        self.adapterPower = PowerTelemetry.validWatts(adapterPower) ?? 0
        self.adapterConnected = adapterConnected; self.isCharging = isCharging
        self.systemAvailable = systemAvailable && PowerTelemetry.validWatts(systemLoad) != nil
        self.adapterAvailable = adapterAvailable && PowerTelemetry.validWatts(adapterPower) != nil
        self.powerSourceAvailable = powerSourceAvailable
    }
    var telemetry: PowerTelemetry { .init(system: systemAvailable ? systemLoad : nil, adapter: adapterAvailable ? adapterPower : nil) }
    var heroWatts: Double { telemetry.system ?? 0 }
    var adapterDisplayWatts: Double { telemetry.adapter ?? 0 }
    var statusLabel: String { powerSourceAvailable ? (isCharging ? "Charging" : (adapterConnected ? "On AC Power" : "On Battery")) : "Power source unavailable" }
    var statusColor: Color { powerSourceAvailable ? (isCharging ? .green : (adapterConnected ? .cyan : .orange)) : .gray }
}

struct PowerSplitBar: View {
    let reading: SystemPowerReading
    var body: some View {
        VStack(spacing: 1) {
            bar(reading.telemetry.systemFraction, color: .cyan)
            bar(reading.telemetry.adapterFraction, color: .green)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power readings: system load above, adapter input below")
        .accessibilityValue("System \(reading.telemetry.system.map { String(format: "%.2f W", $0) } ?? "unavailable"); adapter \(reading.telemetry.adapter.map { String(format: "%.2f W", $0) } ?? "unavailable")")
        .help("Top: system load; bottom: adapter sensor. Relative bars share a scale. Missing readings have no filled bar.")
    }
    private func bar(_ fraction: Double, color: Color) -> some View {
        GeometryReader { geometry in
            Capsule().fill(Color.white.opacity(0.12)).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: max(0, geometry.size.width) * CGFloat(fraction))
            }
        }
    }
}
#endif
