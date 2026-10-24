#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct MonitoringSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var alerts = SystemAlertsManager.shared
    var body: some View {
        Form {
            Section("Menu-bar readouts") {
                Toggle("Show menu-bar readouts", isOn: $settings.settings.monitoringMenuBarReadoutsEnabled)
                Toggle("CPU usage", isOn: $settings.settings.monitoringReadoutShowCPU)
                Toggle("Memory usage", isOn: $settings.settings.monitoringReadoutShowMemory)
                Toggle("Network rates", isOn: $settings.settings.monitoringReadoutShowNetwork)
                Text("Shows a separate menu-bar item. Network rates cover eligible active interfaces; loopback, VPN and virtual interfaces are excluded. Readouts stop polling when disabled.").foregroundStyle(.secondary)
                if !settings.settings.monitoringReadoutShowCPU && !settings.settings.monitoringReadoutShowMemory && !settings.settings.monitoringReadoutShowNetwork {
                    Text("Select at least one readout to show the item.").foregroundStyle(.secondary)
                }
            }
            Section("System alerts") {
                Toggle("Enable alerts", isOn: $settings.settings.monitoringAlertsEnabled)
                Text("Enabling alerts asks macOS for notification permission. You can configure thresholds first. Notifications respect macOS delivery settings.").foregroundStyle(.secondary)
                Text(notificationStatus).font(.caption).foregroundStyle(.secondary)
                Button("Refresh notification status") { alerts.refreshNotificationAccess() }
            }
            Section("CPU and memory") {
                Toggle("Sustained high CPU", isOn: $settings.settings.monitoringAlertSustainedCPUEnabled)
                Slider(value: cpu, in: 50...100, step: 1) { Text("CPU threshold") }.disabled(!settings.settings.monitoringAlertSustainedCPUEnabled)
                Text("\(cpu.wrappedValue, specifier: "%.0f")% CPU for at least 45 seconds · 10-minute cooldown").font(.caption).foregroundStyle(.secondary)
                Toggle("Memory pressure", isOn: $settings.settings.monitoringAlertMemoryPressureEnabled)
                Text("Uses macOS memory-pressure warnings, rather than a percentage of RAM used.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Storage and battery") {
                Toggle("Low disk space for your home folder", isOn: $settings.settings.monitoringAlertLowDiskEnabled)
                Slider(value: disk, in: 2...50, step: 1) { Text("Disk threshold") }.disabled(!settings.settings.monitoringAlertLowDiskEnabled)
                Text("Below \(disk.wrappedValue, specifier: "%.0f") GiB available, including purgeable space. Checks every 15 minutes and after volume/wake changes.").font(.caption).foregroundStyle(.secondary)
                Toggle("Low battery", isOn: $settings.settings.monitoringAlertLowBatteryEnabled)
                Slider(value: battery, in: 5...50, step: 1) { Text("Battery threshold") }.disabled(!settings.settings.monitoringAlertLowBatteryEnabled)
                Text("At or below \(battery.wrappedValue, specifier: "%.0f")% while on battery. Rearms on external power or more than five points above the threshold.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Temperature") {
                Toggle("Sustained high CPU temperature", isOn: $settings.settings.monitoringAlertTemperatureEnabled)
                Slider(value: temperature, in: 70...105, step: 1) { Text("Temperature threshold") }.disabled(!settings.settings.monitoringAlertTemperatureEnabled)
                Text("\(temperature.wrappedValue, specifier: "%.0f")°C for at least 30 seconds. Requires usable CPU temperature sensors and the installed helper; unsupported hardware may provide no reading.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear { alerts.refreshNotificationAccess() }
    }
    private var notificationStatus: String {
        switch alerts.notificationAccess {
        case .allowed: "macOS notification access is allowed."
        case .denied: "Notifications are denied. Review Sapphire in System Settings → Notifications."
        case .unknown: "Notification access has not been confirmed."
        }
    }
    private var cpu: Binding<Double> { Binding(get: { MonitoringThresholds.cpu(settings.settings.monitoringAlertCPUThreshold) }, set: { settings.settings.monitoringAlertCPUThreshold = MonitoringThresholds.cpu($0) }) }
    private var disk: Binding<Double> { Binding(get: { MonitoringThresholds.disk(settings.settings.monitoringAlertDiskThresholdGB) }, set: { settings.settings.monitoringAlertDiskThresholdGB = MonitoringThresholds.disk($0) }) }
    private var battery: Binding<Double> { Binding(get: { MonitoringThresholds.battery(settings.settings.monitoringAlertLowBatteryThreshold) }, set: { settings.settings.monitoringAlertLowBatteryThreshold = MonitoringThresholds.battery($0) }) }
    private var temperature: Binding<Double> { Binding(get: { MonitoringThresholds.temperature(settings.settings.monitoringAlertTemperatureThreshold) }, set: { settings.settings.monitoringAlertTemperatureThreshold = MonitoringThresholds.temperature($0) }) }
}
#endif
