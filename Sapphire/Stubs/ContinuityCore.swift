//
//  ContinuityCore.swift
//  Sapphire
//
//  Created by Shariq Charolia on 2026-09-15

#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI
import CryptoKit
import UserNotifications

enum ContinuityDeviceType: String, Codable, Sendable {
    case phone, tablet, mac, unknown

    var glyph: String {
        switch self {
        case .phone: "iphone"
        case .tablet: "ipad"
        case .mac: "macbook"
        case .unknown: "questionmark.circle"
        }
    }
}

enum ContinuityCapability: String, Codable, CaseIterable, Sendable {
    case clipboard, notifications, media, status, hotspot, files, handoff
    case mirroring, camera, sidecar, universalControl, sms, scan, sketch
    case audioCast, widgets, externalActivities, microphone
}

enum ContinuityLinkState: String, Equatable {
    case offline, nearby, connected, online

    var isUsable: Bool { self == .connected || self == .online }
}

enum ContinuityNetworkKind: String, Codable {
    case wifi, cellular, none
}

struct ContinuityConnectivitySnapshot: Equatable {
    enum Severity: Equatable {
        case noDevice, healthy, degraded, offline
    }

    var severity: Severity = .noDevice
    var deviceName = ""
    var linkState: ContinuityLinkState = .offline
    var headline = ""
    var detail = ""
    var suggestion: String?
    var bluetoothWarning: String?
    var linkError: String?
    var phoneBatteryPercent: Int?
    var phoneCharging = false
    var phoneNetwork: ContinuityNetworkKind?
    var phoneSSID: String?
    var phoneSignalLevel: Int?
    var phoneCarrier: String?
    var rssi: Int?
    var isRelayed = false

    var hasDevice: Bool { severity != .noDevice }
    var isIssue: Bool { severity == .degraded || severity == .offline }

    static let none = ContinuityConnectivitySnapshot()
}

struct ContinuityPairedPeer: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var deviceType: ContinuityDeviceType
}

@MainActor
@Observable
final class ContinuityPeer: Identifiable {
    nonisolated let record: ContinuityPairedPeer
    nonisolated var id: String { record.id }
    var linkState: ContinuityLinkState = .offline
    var capabilities: Set<ContinuityCapability> = []

    init(record: ContinuityPairedPeer) {
        self.record = record
    }

    var displayName: String { record.name }
    func supports(_ capability: ContinuityCapability) -> Bool { capabilities.contains(capability) }
}

struct ContinuityMediaState: Codable, Equatable {
    var sessionId: String
    var appId: String
    var appName: String
    var title: String
    var artist: String?
    var album: String?
    var isPlaying: Bool
    var positionMs: Int
    var durationMs: Int
    var canNext: Bool
    var canPrev: Bool
    var canSeek: Bool
    var canToggle: Bool
    var artwork: String?

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        appId = try values.decodeIfPresent(String.self, forKey: .appId) ?? ""
        sessionId = try values.decodeIfPresent(String.self, forKey: .sessionId) ?? appId
        appName = try values.decodeIfPresent(String.self, forKey: .appName) ?? appId
        title = try values.decodeIfPresent(String.self, forKey: .title) ?? ""
        artist = try values.decodeIfPresent(String.self, forKey: .artist)
        album = try values.decodeIfPresent(String.self, forKey: .album)
        isPlaying = try values.decodeIfPresent(Bool.self, forKey: .isPlaying) ?? false
        positionMs = try values.decodeIfPresent(Int.self, forKey: .positionMs) ?? 0
        durationMs = try values.decodeIfPresent(Int.self, forKey: .durationMs) ?? 0
        canNext = try values.decodeIfPresent(Bool.self, forKey: .canNext) ?? false
        canPrev = try values.decodeIfPresent(Bool.self, forKey: .canPrev) ?? false
        canSeek = try values.decodeIfPresent(Bool.self, forKey: .canSeek) ?? false
        canToggle = try values.decodeIfPresent(Bool.self, forKey: .canToggle) ?? true
        artwork = try values.decodeIfPresent(String.self, forKey: .artwork)
    }
}

enum ContinuityMediaAction: String, Codable {
    case play, pause, toggle, next, previous, seek, stop
}

enum ContinuityActivitySlotKind: String, Codable {
    case icon, text, progress, timer, image, none
}

struct ContinuityActivitySlot: Codable, Equatable {
    var kind: ContinuityActivitySlotKind
    var text: String?
    var glyph: String?
    var imageDigest: String?
    var tintHex: String?
    var progress: Double?
}

struct ContinuityActivityProgress: Codable, Equatable {
    var current: Int
    var max: Int
    var indeterminate: Bool
}

struct ContinuityExternalActivity: Codable, Equatable, Identifiable {
    var key: String
    var appId: String
    var appName: String
    var title: String
    var text: String?
    var left: ContinuityActivitySlot
    var right: ContinuityActivitySlot
    var progress: ContinuityActivityProgress?

    var id: String { key }
}

struct ContinuityLiveExternalActivity: Identifiable, Equatable {
    var activity: ContinuityExternalActivity
    var peerID: String
    var peerName: String
    var appIcon: NSImage?
    var leftImage: NSImage?
    var rightImage: NSImage?
    var expandedImage: NSImage?
    var lastUpdated: Date

    var id: String { activity.key }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.activity == rhs.activity }
}

typealias ContinuityMirroredNotification = PhoneNotification

@MainActor
final class ContinuityNotificationBridge: ObservableObject {
    @Published private(set) var latest: ContinuityMirroredNotification?
    @Published private(set) var notifications: [PhoneNotification] = []
    @Published var actionStatus = ""
    @Published var composingNotificationID: String?
    @Published private(set) var actionKey: String?
    @Published private(set) var actionRequestID: String?
    private var actionTimeout: Task<Void, Never>?
    private var store = PhoneNotificationStore()
    private var pending: [PhoneNotification] = []
    private var bannerTask: Task<Void, Never>?

    func accept(_ entry: PhoneNotification) {
        let mutedAppIDs = Set(SettingsModel.shared.current.continuityNotificationMutedApps.keys)
        guard !mutedAppIDs.contains(entry.appId) else { return }
        let alert = store.accept(entry, mutedAppIDs: mutedAppIDs)
        guard store.contains(key: entry.key, revision: entry.revision) else { return }
        notifications = store.entries
        pending.removeAll { $0.key == entry.key || !store.contains(key: $0.key, revision: $0.revision) }
        if let latest, !store.contains(key: latest.key, revision: latest.revision), latest.key != entry.key { clearLatest() }
        if alert {
            SmartInboxMonitor.shared.ingestNotification(id: "phone:" + entry.id, source: entry.appName, title: entry.title, body: entry.text, date: Date())
            if latest == nil || latest?.key == entry.key { latest = entry }
            else { pending.append(entry); pending = Array(pending.suffix(30)) }
            if SettingsModel.shared.current.continuityNotificationsAsBanners { postBanner(entry) }
        }
    }

    func remove(key: String, revision: String) {
        guard let entry = store.entries.first(where: { $0.key == key && $0.revision == revision }),
              store.remove(key: key, revision: revision) else { return }
        completeRemoval(entry)
    }

    func dismissLocally(_ entry: PhoneNotification) {
        store.dismiss(entry)
        completeRemoval(entry)
    }

    private func completeRemoval(_ entry: PhoneNotification) {
        notifications = store.entries
        pending.removeAll { $0.id == entry.id }
        if latest?.id == entry.id { clearLatest() }
        if composingNotificationID == entry.id { composingNotificationID = nil }
        if !notifications.contains(where: { $0.key == entry.key }) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [bannerID(entry.key)])
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [bannerID(entry.key)])
        }
        (NSApp.delegate as? AppDelegate)?.liveActivityManager.dismissContinuityNotification(id: entry.id)
    }

    func removeMutedApps(_ appIDs: Set<String>) {
        let removed = store.removeApps(appIDs)
        // Prune the whole queue before promoting the next alert, so another
        // notification from a muted app cannot become visible during cleanup.
        pending.removeAll { appIDs.contains($0.appId) }
        for entry in removed { completeRemoval(entry) }
        if let actionKey, removed.contains(where: { $0.key == actionKey }) {
            actionTimeout?.cancel(); actionTimeout = nil
            actionRequestID = nil; self.actionKey = nil; actionStatus = ""
        }
    }

    func clearLatest() { latest = pending.isEmpty ? nil : pending.removeFirst() }
    func contains(key: String, revision: String) -> Bool { store.contains(key: key, revision: revision) }
    func reset() {
        SmartInboxMonitor.shared.removePhoneItems()
        let identifiers = notifications.map { bannerID($0.key) }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        store.reset(); notifications = []; pending = []; latest = nil; actionStatus = ""
        composingNotificationID = nil
        actionTimeout?.cancel(); actionTimeout = nil; actionRequestID = nil; actionKey = nil
    }

    func beginAction(for entry: PhoneNotification) -> String? {
        guard actionRequestID == nil else { return nil }
        let requestID = UUID().uuidString
        actionKey = entry.key; actionRequestID = requestID
        actionStatus = "Waiting for phone…"
        actionTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self, self.actionRequestID == requestID else { return }
            self.actionStatus = "The phone did not respond. Check its connection and unlock it before retrying."
            self.actionRequestID = nil
        }
        return requestID
    }

    func finishAction(requestID: String, message: String) {
        guard requestID == actionRequestID else { return }
        actionTimeout?.cancel(); actionTimeout = nil
        actionRequestID = nil; actionStatus = message
    }

    private func bannerID(_ key: String) -> String {
        "sapphire-phone-" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func category(for entry: PhoneNotification) -> UNNotificationCategory {
        let actions: [UNNotificationAction] = entry.actions.map { action in
            if action.allowsReply {
                return UNTextInputNotificationAction(identifier: action.id, title: action.title,
                    options: [], textInputButtonTitle: "Send", textInputPlaceholder: "Reply")
            }
            return UNNotificationAction(identifier: action.id, title: action.title, options: [])
        }
        return UNNotificationCategory(identifier: bannerID(entry.id), actions: actions,
            intentIdentifiers: [], options: entry.clearable ? [.customDismissAction] : [])
    }

    private func postBanner(_ entry: PhoneNotification) {
        let previous = bannerTask
        bannerTask = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, self.contains(key: entry.key, revision: entry.revision),
                  SettingsModel.shared.current.continuityNotificationsAsBanners,
                  let peerID = ContinuityManager.shared.activePeerID else { return }
            let center = UNUserNotificationCenter.current()
            let existing = await center.notificationCategories()
            guard self.contains(key: entry.key, revision: entry.revision),
                  SettingsModel.shared.current.continuityNotificationsAsBanners else { return }
            var categories = Set(existing.filter { !$0.identifier.hasPrefix("sapphire-phone-") })
            for active in self.notifications { categories.insert(self.category(for: active)) }
            center.setNotificationCategories(categories)
            let content = UNMutableNotificationContent()
            content.title = entry.appName
            content.subtitle = entry.title
            content.body = entry.text
            content.userInfo = ["continuityPeerID": peerID, "continuityKey": entry.key,
                                "continuityRevision": entry.revision]
            content.categoryIdentifier = self.bannerID(entry.id)
            let id = self.bannerID(entry.key)
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                if !self.contains(key: entry.key, revision: entry.revision) {
                    center.removeDeliveredNotifications(withIdentifiers: [id])
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                }
            } catch {
                self.actionStatus = "macOS banners are unavailable. Allow notifications for Sapphire in System Settings."
            }
        }
    }

}

@MainActor
final class ContinuityExternalActivityBridge: ObservableObject {
    @Published private(set) var featured: ContinuityLiveExternalActivity?
}

@MainActor
final class ContinuityMediaBridge: ObservableObject {
    @Published private(set) var phoneMedia: ContinuityMediaState?
    @Published private(set) var phoneArtwork: NSImage?
    @Published private(set) var phoneDeviceName: String?
    var shouldSurfacePhoneMedia: Bool { phoneMedia != nil }
    func acceptReconstructed(_ state: ContinuityMediaState?, deviceName: String?) {
        phoneMedia = state.flatMap { $0.sessionId.isEmpty || ($0.title.isEmpty && !$0.isPlaying) ? nil : $0 }
        phoneDeviceName = deviceName
        phoneArtwork = nil
    }
}

final class ContinuityHandoffBridge {
    static let openActionID = "CONTINUITY_OPEN"
    func handleBannerTap() {}
}

@MainActor
@Observable
final class ContinuityManager {
    static let shared = ContinuityManager()

    private(set) var peers: [ContinuityPeer] = []
    private(set) var connectivity: ContinuityConnectivitySnapshot = .none
    var connectedPeer: ContinuityPeer? { peers.first { $0.linkState.isUsable } }
    var activePeerID: String? { connectedPeer?.id }

    let notificationBridge = ContinuityNotificationBridge()
    let liveActivityBridge = ContinuityExternalActivityBridge()
    let mediaBridge = ContinuityMediaBridge()
    let handoffBridge = ContinuityHandoffBridge()

    private init() {}

    func startIfEnabled() {
        if SettingsModel.shared.current.continuityEnabled { ReconstructedPhoneLink.shared.start() }
    }
    func stop() { ReconstructedPhoneLink.shared.disconnect() }
    func sendMediaCommand(_ action: ContinuityMediaAction, seekMs: Int? = nil) {
        ReconstructedPhoneLink.shared.sendMedia(action.rawValue, seekMs: seekMs)
    }
    func acceptReconstructedConnection(_ snapshot: ContinuityConnectivitySnapshot, record: ContinuityPairedPeer?) {
        connectivity = snapshot
        if let record {
            if peers.first?.id != record.id {
                let peer = ContinuityPeer(record: record)
                peer.capabilities = [.clipboard, .media, .status, .notifications]
                peer.linkState = .connected
                peers = [peer]
            }
        } else {
            peers = []
            mediaBridge.acceptReconstructed(nil, deviceName: nil)
        }
    }
    func acceptReconstructedMedia(_ state: ContinuityMediaState, deviceName: String?) {
        mediaBridge.acceptReconstructed(state, deviceName: deviceName)
    }
    func sendFiles(_ urls: [URL], toPeerID peerID: String) {
        guard peerID == activePeerID, connectedPeer?.id == peerID else { return }
        ReconstructedPhoneLink.shared.sendFilesToPhone(urls)
    }
    func dismissNotificationOnPhone(peerID: String, key: String, revision: String? = nil) {
        guard peerID == activePeerID,
              let entry = notificationBridge.notifications.first(where: { $0.key == key }),
              revision == nil || revision == entry.revision else { return }
        ReconstructedPhoneLink.shared.notificationCommand(entry, action: nil, reply: nil)
    }
    func invokeNotificationAction(peerID: String, key: String, actionId: String, replyText: String?, revision: String? = nil) {
        guard peerID == activePeerID,
              let entry = notificationBridge.notifications.first(where: { $0.key == key }),
              revision == nil || revision == entry.revision,
              let action = entry.actions.first(where: { $0.id == actionId }) else { return }
        ReconstructedPhoneLink.shared.notificationCommand(entry, action: action, reply: replyText)
    }
    func takePhoto() {}
    func scanDocument() {}
    func setActivePeer(id: String) {}
    func unpair(peerID: String) {
        if connectedPeer?.id == peerID { ReconstructedPhoneLink.shared.forget() }
    }
}

@MainActor
final class ContinuityServicesProvider: NSObject {
    static let shared = ContinuityServicesProvider()
    func install() { SystemEnhanceContextMenu.shared.installIfNeeded() }
}

struct ContinuityNotchDetailView: View {
    @Binding var navigationStack: [NotchWidgetMode]
    var body: some View { PhoneNotchStatusView() }
}

struct ContinuityExternalActivityDetailView: View {
    let bridge: ContinuityExternalActivityBridge
    var body: some View { EmptyView() }
}

enum ContinuityNotchActivityView {
    @ViewBuilder static func left(for snapshot: ContinuityConnectivitySnapshot) -> some View {
        Image(systemName: "iphone").foregroundStyle(snapshot.severity.tint)
    }
    @ViewBuilder static func right(for snapshot: ContinuityConnectivitySnapshot) -> some View {
        HStack(spacing: 4) {
            PhoneSignalBars(level: snapshot.phoneSignalLevel)
            if let carrier = snapshot.phoneCarrier { Text(carrier).font(.caption2).lineLimit(1) }
        }
    }
}

enum ContinuityExternalActivityView {
    @ViewBuilder static func left(for activity: ContinuityLiveExternalActivity) -> some View { EmptyView() }
    @ViewBuilder static func right(for activity: ContinuityLiveExternalActivity) -> some View { EmptyView() }
}

enum ContinuityMediaActivityView {
    @ViewBuilder static func left(state: ContinuityMediaState, artwork: NSImage?) -> some View { EmptyView() }
    @ViewBuilder static func right(state: ContinuityMediaState, deviceName: String) -> some View { EmptyView() }
}

struct ContinuityNotificationActivityView: View {
    @Environment(\.notchBandHeight) private var notchBandHeight
    @Environment(\.notchActivityCenterGap) private var notchCenterGap
    let entry: ContinuityMirroredNotification
    @ObservedObject var bridge: ContinuityNotificationBridge
    @Binding var isHovered: Bool

    private var centerClearance: CGFloat { notchCenterGap > 0 ? notchCenterGap + 24 : 0 }
    private var panelWidth: CGFloat { max(400, centerClearance + 2 * 120 + 40) }
    private var sideWidth: CGFloat { (panelWidth - 40 - centerClearance) / 2 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Label(entry.appName, systemImage: "iphone")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(entry.appName)
                    .frame(width: sideWidth, alignment: .leading)
                Color.clear.frame(width: centerClearance)
                    .accessibilityHidden(true)
                HStack {
                    Spacer(minLength: 0)
                    if entry.clearable { PhoneNotificationDismissButton(entry: entry) }
                }
                .frame(width: sideWidth)
            }
            .padding(.horizontal, 20)
            .frame(height: notchBandHeight)

            PhoneNotificationCard(entry: entry, showsHeader: false)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 20)
        }
        .frame(width: panelWidth)
        .onHover { isHovered = $0 }
    }
}

extension Notification.Name {
    static let continuityClipboardReceived = Notification.Name("com.shariq.sapphire.continuity.clipboardReceived")
}
#endif
