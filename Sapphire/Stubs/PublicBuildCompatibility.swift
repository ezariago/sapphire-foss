// Compatibility for public code whose private companion implementations are absent.
#if !SAPPHIRE_FULL_BUILD
import AppKit
import Darwin
import SwiftUI
import UserNotifications

extension CleanURLManager {
    func stopMonitoring() { stopPolling() }
}


struct SEQuitProtectionRulesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quit and close protection").font(.headline)
            Text("Hold mode requires holding ⌘Q or ⌘W until the configured interval. Double-press mode requires two distinct presses; extra-modifier mode requires the configured modifier. Menu commands and app-initiated exits are unaffected.")
                .foregroundStyle(.secondary)
            if !AXIsProcessTrusted() {
                Button("Allow Accessibility") { AccessibilityPermission.request() }
            }
        }
    }
}

// The Space Map view is private and has no consumer in the public checkout.
struct StorageSpaceMapSnapshot {
    static func make(from entries: [StorageEntry], maximumItems: Int, used: Int64,
                     total: Int64, deepScanEnabled: Bool,
                     entriesSortedBySize: Bool) -> Self { Self() }
}

enum OCRScreenTextSupport {
    static func indexOfScreen(containing point: CGPoint, in frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }
}

extension ContinuityConnectivitySnapshot.Severity {
    var tint: Color {
        switch self {
        case .noDevice: .secondary
        case .healthy: .green
        case .degraded: .orange
        case .offline: .red
        }
    }
}

extension ContinuityExternalActivity {
    var shortText: String? { text }
}

struct PublicContinuityNotificationBridge {
    func handleNotificationResponse(_ response: UNNotificationResponse) {}
}

struct PublicContinuityFocusState {
    var isApplyingRemoteFocus: Bool { false }
}

extension ContinuityManager {
    var messagesBridge: PublicContinuityNotificationBridge { .init() }
    var callsBridge: PublicContinuityNotificationBridge { .init() }
    var focusModeManager: PublicContinuityFocusState { .init() }
    func openWidgets(focus: Int?) {}
}

enum PublicContinuityMessageKind {
    case earbudCommand, earbudStatus
}

extension ContinuityPeer {
    func send<Payload>(_ kind: PublicContinuityMessageKind, _ payload: Payload) {}
}

struct ContinuityEarbudCommand: Codable, Equatable {
    var action: String
    var stringValue: String? = nil
    var boolValue: Bool? = nil
    var intValue: Int? = nil
}

enum ContinuityBluetoothAddress {
    static func normalize(_ address: String?) -> String? {
        guard let address else { return nil }
        let compact = address.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard compact.count == 12, compact.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let characters = Array(compact.uppercased())
        return stride(from: 0, to: characters.count, by: 2)
            .map { String(characters[$0..<$0 + 2]) }.joined(separator: ":")
    }

    static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs = normalize(lhs), let rhs = normalize(rhs) else { return false }
        return lhs == rhs
    }

    static func dashed(_ address: String?) -> String? {
        normalize(address)?.replacingOccurrences(of: ":", with: "-")
    }
}

enum ContinuityLog {
    static func f(_ message: String) {}
    static func fErr(_ message: String) {}
}

// Wire snapshot required by the public headphone controls. Transport remains a stub.
struct ContinuityEarbudStatus: Codable, Equatable {
    var vendor: String = "none"
    var name: String = ""
    var address: String?
    var connected = false
    var ownedLocally = false
    var noiseMode = "off"
    var ancHigh = true
    var eqPreset = "off"
    var batteryLeft = 0
    var batteryRight = 0
    var batteryCase = 0
    var batteryMain = 0
    var dsee = false
    var seamless = false
    var detectConversations = false
    var ambientLevel = 2
    var supportsANC = false
    var supportsAdaptive = false
    var supportsEQ = true
    var supportsDSEE = false
    var supportsSeamless = false
    var supportsFind = false
    var supportsCustomEQ = false
    var customEQBands: [Int] = Array(repeating: 0, count: 9)
    var bassGain = 0
    var gamingMode = false
    var spatialAudio = false
    var touchpadLocked = false
    var touchLeft: Int = 2
    var touchRight: Int = 2
    var speakSeamlessly = false
    var ancOneEarbud = false
    var autoSwitchAudio = false
    var pauseOnOneBudRemoved = false
    var sidetone = false
    var extraHighAmbient = false
    var amplifyAmbient = false
    var inBandRingtone = false
    var callPathControl = true
    var ambientDuringCall = false
    var detectConversationsDuration = 1
    var outsideDoubleTap = false
    var muteLeft = false
    var muteRight = false
    var wearingLeft = false
    var wearingRight = false
    var fitTesting = false
    var fitLeftGood = false
    var fitRightGood = false
    var supportsGaming = false
    var supportsSpatial = false
    var supportsTouchLock = false
    var supportsFitTest = false
    var supportsAmbientExtras = false
    var supportsCallExtras = false
    var supportsDetectConversations = false
    var supportsExtraClearCall = false
    var supportsPassthrough = false
    var supportsOutsideDoubleTap = false
    var extraClearCall = false
    var passthrough = false
}
#endif
