// Public menu-bar profile models retained from PremiumFeatureModels.swift.
// Original models: Shariq Charolia, 2026-09-15.
#if !SAPPHIRE_FULL_BUILD
import Foundation
enum MenuBarRevealConditionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case batteryBelow, batteryAbove, charging, onBatteryPower
    case focusActive, focusIdentifier, wifiEquals, wifiConnected
    case scriptSucceeds, scriptFails, scriptExitCode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .batteryBelow: "Battery Level Below"
        case .batteryAbove: "Battery Level Above"
        case .charging: "Charging"
        case .onBatteryPower: "On Battery Power"
        case .focusActive: "Shared Focus Status Is Active"
        case .focusIdentifier: "Focus Mode Is"
        case .wifiEquals: "Wi-Fi Network Is"
        case .wifiConnected: "Wi-Fi Connected"
        case .scriptSucceeds: "Script Exits Successfully"
        case .scriptFails: "Script Fails"
        case .scriptExitCode: "Script Exit Code Is"
        }
    }

    var systemImage: String {
        switch self {
        case .batteryBelow, .batteryAbove: "battery.25"
        case .charging: "bolt.fill"
        case .onBatteryPower: "battery.100"
        case .focusActive, .focusIdentifier: "moon.fill"
        case .wifiEquals, .wifiConnected: "wifi"
        case .scriptSucceeds, .scriptFails, .scriptExitCode: "terminal"
        }
    }
}

struct MenuBarRevealCondition: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var kind: MenuBarRevealConditionKind = .batteryBelow
    var batteryThreshold = 20
    var focusIdentifier = ""
    var wifiNetworkName = ""
    var scriptPath = ""
    var scriptArgument = ""
    var scriptExitCode = 0
    var scriptPollInterval: TimeInterval = 30

    init() {}

    init(kind: MenuBarRevealConditionKind) {
        self.kind = kind
    }
}

enum MenuBarProfileDisplayScope: String, Codable, CaseIterable, Sendable {
    case allDisplays, selectedDisplays
}

struct MenuBarDisplayBinding: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String { displayIdentifier }
    var displayIdentifier: String
    var displayLabel = ""
}

struct MenuBarProfile: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name = "New Profile"
    var symbolName = "menubar.rectangle"
    var revealConditions: [MenuBarRevealCondition] = []
    var isEnabled = true
    var bindsToDisplays = false
    var displayScope: MenuBarProfileDisplayScope = .selectedDisplays
    var displayBindings: [MenuBarDisplayBinding] = []
    var bindsToSpaces = false
    var spaceNumbers: [Int] = []
    var bindsToFocus = false
    var focusIdentifiers: [String] = []

    init() {}

    init(name: String) {
        self.name = name
    }

    var summaryText: String {
        revealConditions.isEmpty ? "No conditions" : "\(revealConditions.count) condition(s)"
    }
}

extension Notification.Name {
    static let menuBarProfilesDidChange = Notification.Name("com.sapphire.menuBarProfilesDidChange")
}
#endif
