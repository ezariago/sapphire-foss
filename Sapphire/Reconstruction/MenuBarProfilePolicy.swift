#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Public inputs only. Missing/invalid data never causes a reveal.
struct MenuBarProfileSnapshot: Sendable {
    var batteryPercent: Int?
    var isCharging: Bool?
    var isPluggedIn: Bool?
    var wifiSSID: String?
    var menuBarDisplayIdentifiers: Set<String>?
}

enum MenuBarProfilePolicy {
    static let supportedKinds: [MenuBarRevealConditionKind] = [
        .batteryBelow, .batteryAbove, .charging, .onBatteryPower, .wifiEquals, .wifiConnected
    ]
    static func isSupported(_ profile: MenuBarProfile) -> Bool {
        !profile.bindsToSpaces && !profile.bindsToFocus
            && profile.revealConditions.allSatisfy { supportedKinds.contains($0.kind) }
            && (!profile.bindsToDisplays || profile.displayScope == .allDisplays
                || (profile.displayBindings.count <= 64 && profile.displayBindings.allSatisfy { validIdentifier($0.displayIdentifier) }))
    }
    static func requestsReveal(profiles: [MenuBarProfile], snapshot: MenuBarProfileSnapshot) -> Bool {
        profiles.contains { profile in
            profile.isEnabled && isSupported(profile) && displayMatches(profile, identifiers: snapshot.menuBarDisplayIdentifiers)
                && profile.revealConditions.contains { matches($0, snapshot: snapshot) }
        }
    }
    private static func validIdentifier(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.count <= 128 && !id.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    static func displayMatches(_ profile: MenuBarProfile, identifiers: Set<String>?) -> Bool {
        guard profile.bindsToDisplays else { return true }
        guard let identifiers, !identifiers.isEmpty, identifiers.allSatisfy(validIdentifier) else { return false }
        if profile.displayScope == .allDisplays { return true }
        return profile.displayBindings.contains { identifiers.contains($0.displayIdentifier) }
    }
    static func matches(_ condition: MenuBarRevealCondition, snapshot: MenuBarProfileSnapshot) -> Bool {
        switch condition.kind {
        case .batteryBelow, .batteryAbove:
            guard let level = snapshot.batteryPercent, (0...100).contains(level),
                  (0...100).contains(condition.batteryThreshold) else { return false }
            return condition.kind == .batteryBelow ? level < condition.batteryThreshold : level > condition.batteryThreshold
        case .charging: return snapshot.isCharging == true && snapshot.isPluggedIn == true
        case .onBatteryPower: return snapshot.isPluggedIn == false
        case .wifiConnected: return snapshot.wifiSSID.map { !$0.isEmpty } ?? false
        case .wifiEquals:
            guard !condition.wifiNetworkName.isEmpty, let name = snapshot.wifiSSID, !name.isEmpty else { return false }
            return name == condition.wifiNetworkName
        case .focusActive, .focusIdentifier, .scriptSucceeds, .scriptFails, .scriptExitCode:
            return false
        }
    }
}
#endif
