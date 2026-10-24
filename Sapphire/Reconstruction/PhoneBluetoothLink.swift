// Replacement BLE Continuity client. No private binaries are linked or loaded.
#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import CoreBluetooth
import CoreLocation
import CryptoKit
import Security
import OSLog

struct ReconstructedPhoneRecord: Codable {
    let id: String
    let name: String
    let peripheralID: UUID
    let publicKey: Data
    let linkKey: Data
}

enum ReconstructedPhoneStore {
    private static let service = "com.sapphire.local-reconstruction.phone-pairing.v1"
    static func load() throws -> ReconstructedPhoneRecord? {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: "phone", kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne]
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode(ReconstructedPhoneRecord.self, from: data)
    }
    static func save(_ record: ReconstructedPhoneRecord) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: "phone"]
        let data = try JSONEncoder().encode(record)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(add as CFDictionary, nil)
            guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
    static func remove() throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword,
            kSecAttrService: service, kSecAttrAccount: "phone"] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

private struct PhoneNotificationPreferences: Equatable {
    let enabled: Bool
    let general: Bool
    let system: Bool
    let banners: Bool
    let mutedApps: [String: String]
    init(_ settings: Settings) {
        enabled = settings.continuityEnabled && settings.continuityNotifications
        general = settings.continuityNotificationsGeneral
        system = settings.continuityNotificationsSystem
        banners = settings.continuityNotificationsAsBanners
        mutedApps = settings.continuityNotificationMutedApps
    }
}

@MainActor
final class ReconstructedPhoneLink: NSObject, ObservableObject {
    static let shared = ReconstructedPhoneLink()
    private static let service = CBUUID(string: "A17E0001-4D61-6373-6170-706C696E6B00")
    private static let inbox = CBUUID(string: "A17E0002-4D61-6373-6170-706C696E6B00")
    private static let outbox = CBUUID(string: "A17E0003-4D61-6373-6170-706C696E6B00")
    private static let control = CBUUID(string: "A17E0004-4D61-6373-6170-706C696E6B00")
    private static let companionService = CBUUID(string: "DAB10001-5A50-434F-4D50-414E494F4E31")
    private static let companionInbox = CBUUID(string: "DAB10002-5A50-434F-4D50-414E494F4E31")
    private static let companionOutbox = CBUUID(string: "DAB10003-5A50-434F-4D50-414E494F4E31")
    private static let companionControl = CBUUID(string: "DAB10004-5A50-434F-4D50-414E494F4E31")
    private var activeCompanion = false
    private var serviceUUID: CBUUID { activeCompanion ? Self.companionService : Self.service }
    private var inboxUUID: CBUUID { activeCompanion ? Self.companionInbox : Self.inbox }
    private var outboxUUID: CBUUID { activeCompanion ? Self.companionOutbox : Self.outbox }
    private var controlUUID: CBUUID { activeCompanion ? Self.companionControl : Self.control }
    private let logger = Logger(subsystem: "com.sapphire.local", category: "PhoneReconstruction")

    struct NearbyPhone: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let advertisement: PhoneAdvertisement?
        let lastSeen: Date
        let isCompanion: Bool
    }
    @Published private(set) var nearby: [NearbyPhone] = []
    @Published private(set) var status = "Phone integration has not been started."
    @Published private(set) var qrPayload: String?
    @Published private(set) var sas: String?
    @Published private(set) var awaitingConfirmation = false
    @Published private(set) var isSecure = false
    @Published private(set) var isScanning = false
    @Published private(set) var isConnecting = false
    @Published private(set) var pairedName: String?
    @Published private(set) var phoneStatus = PhoneDeviceStatus()
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var mediaTitle = ""
    @Published private(set) var receivedText: String?
    @Published private(set) var lastNotification = ""
    @Published private(set) var receivedLink: URL?
    @Published private(set) var handoffStatus = ""
    @Published private(set) var handoffState = ""
    @Published private(set) var handoffSupported = false
    @Published private(set) var handoffPendingID: String?
    @Published private(set) var phoneDraftsSupported = false
    @Published private(set) var phoneDraftPendingID: String?
    @Published private(set) var phoneDraftStatus = ""
    private var phoneDraftTimeout: Task<Void, Never>?
    private var handoffTimeout: Task<Void, Never>?
    private var receivedHandoffIDs: [String] = []
    @Published private(set) var lastError: String?

    @Published var automaticClipboard = UserDefaults.standard.object(forKey: "reconstructedContinuity.autoClipboard.v1") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(automaticClipboard, forKey: "reconstructedContinuity.autoClipboard.v1")
            updateClipboardMonitoring()
        }
    }
    @Published private(set) var hotspotStatus = ""
    @Published private(set) var isHotspotBusy = false
    @Published private(set) var hotspotConnected = false
    @Published private(set) var hotspotInternet = false
    @Published private(set) var hotspotCanStop = false
    private var notificationSettings: AnyCancellable?
    private var appliedNotificationPreferences: PhoneNotificationPreferences?
    private var clipboardToken: PasteboardChangeMonitor.Token?
    private var clipboardChanges = PhoneClipboardChanges(baseline: 0)
    private let hotspotJoiner = PhoneHotspotJoiner()
    private var hotspotTask: Task<Void, Never>?
    private var hotspotRequestID: UUID?
    private var hotspotCredentialsReceived = false
    private var hotspotProbeOnly = false
    private let hotspotLocation = CLLocationManager()
    private var hotspotNeedsLocation = false

    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var subscribed = false
    private var chunks: [Data] = []
    private var writeInFlight = false
    private var framing = PhoneGATTFraming()
    private var messageID: UInt16 = 0
    private var pairing: PhonePairingSession?
    private var pendingPeer: ReconstructedPhoneRecord?
    private var pendingSAS: String?
    private var localConfirmed = false
    private var phoneConfirmed = false
    private var trusted: ReconstructedPhoneRecord?
    private var macNonce: Data?
    private var encryption: PhoneBLESession?
    private var connectedID: String?
    private var connectionTimeout: Task<Void, Never>?
    private var pairingTimeout: Task<Void, Never>?
    private var heartbeat: Task<Void, Never>?
    private var lastReceived = Date.distantPast
    private var wantsScan = false
    private var reconnectAllowed = false
    private var isSleeping = false
    private var recoveryTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var diagnosticDirectory: URL?
    private var diagnosticTimer: Timer?
    private var diagnosticSubscription: AnyCancellable?
    private var lastMessageType = ""

    // Explicit local developer mode: no network listener, no stored keys or codes
    // in snapshots, and no command for approving pairing or accessing phone data.
    func enableDiagnostics() {
        guard diagnosticDirectory == nil else { return }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapphire-phone-diagnostics-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            diagnosticDirectory = directory
            diagnosticSubscription = objectWillChange.sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.writeDiagnosticSnapshot() }
            }
            diagnosticTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.readDiagnosticCommand()
                    self?.writeDiagnosticSnapshot()
                }
            }
            writeDiagnosticSnapshot()
        } catch { fail(error) }
    }

    private func writeDiagnosticSnapshot() {
        guard let diagnosticDirectory else { return }
        let activityManager = (NSApp.delegate as? AppDelegate)?.liveActivityManager
        let visibleID = activityManager?.activityContent.id?.base as? String
        let media = ContinuityManager.shared.mediaBridge.phoneMedia
        let fixtureMedia = media?.appId == "dev.sapphire.companion"
            && ["Sapphire media fixture 1", "Sapphire media fixture 2"].contains(media?.title ?? "")
        let snapshot: [String: Any] = [
            "status": status, "error": lastError ?? "", "isScanning": isScanning,
            "isConnecting": isConnecting, "isSecure": isSecure, "pairingActive": pairing != nil,
            "isSleeping": isSleeping, "reconnectAllowed": reconnectAllowed,
            "recoveryPending": recoveryTask != nil,
            "hasConfirmationCode": sas != nil, "subscribed": subscribed,
            "bluetoothState": central?.state.rawValue ?? -1, "queuedChunks": chunks.count,
            "lastMessageType": lastMessageType,
            "handoffFixtureReceived": receivedLink?.absoluteString == "https://example.com/sapphire-handoff-test",
            "handoffState": handoffState,
            "mediaFixturePresent": fixtureMedia,
            "mediaFixturePlaying": fixtureMedia && media?.isPlaying == true,
            "mediaFixtureTrack": fixtureMedia ? (media?.title.hasSuffix("2") == true ? 2 : 1) : 0,
            "mediaFixturePositionMs": fixtureMedia ? (media?.positionMs ?? -1) : -1,
            "notificationFixtureMuted": SettingsModel.shared.current.continuityNotificationMutedApps["dev.sapphire.companion"] != nil,
            "phoneNotificationCount": ContinuityManager.shared.notificationBridge.notifications.count,
            "hasPhoneNotificationAlert": ContinuityManager.shared.notificationBridge.latest != nil,
            "phoneNotificationActivityVisible": activityManager?.currentActivity == .continuityNotification,
            "notificationFixtureActivityVisible": activityManager?.currentActivity == .continuityNotification
                && visibleID?.contains("|sapphire-notification-fixture|") == true,
            "notificationFixtureState": ContinuityManager.shared.notificationBridge.notifications.first(where: \.isDiagnosticFixture)?.diagnosticFixtureState ?? "absent",
            "phoneSignalLevel": phoneStatus.signalLevel ?? -1, "phoneCarrier": phoneStatus.carrier ?? "",
            "phoneCharging": phoneStatus.charging, "phoneNetwork": phoneStatus.network ?? "",
            "automaticClipboard": automaticClipboard, "hotspotStatus": hotspotStatus,
            "hotspotLocationAuthorization": hotspotLocation.authorizationStatus.rawValue,
            "hotspotInternet": hotspotInternet, "hotspotCanStop": hotspotCanStop,
            "isHotspotBusy": isHotspotBusy, "hotspotConnected": hotspotConnected,
            "qrPayload": qrPayload ?? "", // Public ephemeral challenge, never a private key.
            "nearby": nearby.map { ["id": $0.id.uuidString, "rssi": $0.rssi,
                "readyToPair": $0.advertisement?.isPairing == true] as [String: Any] }
        ]
        do {
            let file = diagnosticDirectory.appendingPathComponent("state.json")
            try JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys])
                .write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { logger.error("Could not save phone diagnostics") }
    }

    private func readDiagnosticCommand() {
        guard let diagnosticDirectory else { return }
        let file = diagnosticDirectory.appendingPathComponent("command.json")
        guard let data = try? Data(contentsOf: file), data.count < 1024 else { return }
        try? FileManager.default.removeItem(at: file)
        guard let command = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return }
        switch command["action"] {
        case "pair": beginPairing()
        case "scan": start()
        case "connect":
            if let id = command["id"].flatMap(UUID.init(uuidString:)) { connect(id) }
        case "disconnect": disconnect()
        case "simulate-sleep": prepareForSleep()
        case "simulate-wake": resumeAfterWake()
        case "hotspot": requestHotspot()
        case "hotspot-probe": beginHotspotRequest(probeOnly: true)
        case "hotspot-leave": leaveHotspot()
        case "clipboard-on": automaticClipboard = true
        case "clipboard-off": automaticClipboard = false
        case "notification-test-action": notificationFixtureCommand("action")
        case "notification-test-reply": notificationFixtureCommand("reply")
        case "notification-test-dismiss": notificationFixtureCommand("dismiss")
        case "handoff-test-send": sendLinkToPhone("https://example.com/sapphire-handoff-test")
        case "notification-test-mute":
            SettingsModel.shared.settings.continuityNotificationMutedApps["dev.sapphire.companion"] = "Sapphire Companion"
        case "notification-test-unmute":
            SettingsModel.shared.settings.continuityNotificationMutedApps.removeValue(forKey: "dev.sapphire.companion")
        case "media-test-play", "media-test-pause", "media-test-toggle", "media-test-next", "media-test-previous", "media-test-seek", "media-test-stop":
            if let media = ContinuityManager.shared.mediaBridge.phoneMedia,
               media.appId == "dev.sapphire.companion",
               ["Sapphire media fixture 1", "Sapphire media fixture 2"].contains(media.title),
               let action = command["action"]?.replacingOccurrences(of: "media-test-", with: "") {
                sendMedia(action, seekMs: action == "seek" ? 42000 : nil)
            }
        case "quit": NSApp.terminate(nil)
        default: break
        }
        writeDiagnosticSnapshot()
    }

    // These developer commands can only act on our fixed debug Android fixture.
    // They cannot select arbitrary notifications or supply arbitrary reply text.
    private func notificationFixtureCommand(_ kind: String) {
        guard diagnosticDirectory != nil,
              let entry = ContinuityManager.shared.notificationBridge.notifications.first(where: \.isDiagnosticFixture) else { return }
        if kind == "dismiss" { notificationCommand(entry, action: nil, reply: nil) }
        else if let action = entry.actions.first(where: {
            kind == "reply" ? ($0.title == "Reply" && $0.allowsReply) : ($0.title == "Test action" && !$0.allowsReply)
        }) {
            notificationCommand(entry, action: action, reply: kind == "reply" ? "Sapphire reply fixture" : nil)
        }
    }

    private var macID: String {
        let key = "reconstructedContinuity.macDeviceID.v1"
        if let value = UserDefaults.standard.string(forKey: key) { return value }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
    private var macName: String { (Host.current().localizedName ?? "Mac") + " (Local Build)" }

    override private init() {
        super.init()
        hotspotLocation.delegate = self
        appliedNotificationPreferences = PhoneNotificationPreferences(SettingsModel.shared.current)
        notificationSettings = SettingsModel.shared.changes(of: PhoneNotificationPreferences.init)
            .sink { [weak self] preferences in
                MainActor.assumeIsolated { self?.updateNotificationPreferences(preferences) }
            }
        let notifications = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(notifications.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.prepareForSleep() }
            })
        workspaceObservers.append(notifications.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeAfterWake() }
            })
        do { trusted = try ReconstructedPhoneStore.load(); pairedName = trusted?.name }
        catch { lastError = "Could not read the saved phone pairing: \(error.localizedDescription)" }
    }

    func start() {
        wantsScan = true
        reconnectAllowed = true
        lastError = nil
        guard !isSleeping else { return }
        recoveryTask?.cancel(); recoveryTask = nil
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main,
                options: [CBCentralManagerOptionShowPowerAlertKey: true])
        } else { scanIfReady() }
    }

    func beginPairing() {
        disconnect()
        pairing = PhonePairingSession()
        do { qrPayload = try pairing?.qr(macID: macID, name: macName) }
        catch { fail(error); return }
        status = "Open Pair your Mac on the phone. Connect it below, then scan this code using Pair with a code."
        pairingTimeout?.cancel()
        pairingTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(180))
            guard !Task.isCancelled, let self, self.pairing != nil else { return }
            self.fail(PhoneWireError.expired)
            self.disconnect()
        }
        start()
    }

    func connect(_ id: UUID) {
        guard peripheral == nil, let found = peripherals[id], central?.state == .poweredOn else { return }
        if pairing == nil {
            guard let trusted, PhoneDiscoveryPolicy.isKnownPhone(savedDeviceID: trusted.id,
                savedPeripheralID: trusted.peripheralID, candidateID: id,
                advertisement: nearby.first(where: { $0.id == id })?.advertisement) else {
                status = "Show a pairing code before connecting a new phone."
                return
            }
        }
        central?.stopScan(); isScanning = false
        activeCompanion = nearby.first(where: { $0.id == id })?.isCompanion == true
        peripheral = found
        found.delegate = self
        isConnecting = true
        status = "Connecting over Bluetooth…"
        central?.connect(found)
        armTimeout()
    }

    func confirmPairing() {
        guard awaitingConfirmation, pendingSAS != nil else { return }
        localConfirmed = true
        awaitingConfirmation = false
        status = "Mac confirmed. Confirm the same code on your phone."
        finishPairingIfConfirmed()
    }

    func disconnect() {
        recoveryTask?.cancel(); recoveryTask = nil
        wantsScan = false
        reconnectAllowed = false
        central?.stopScan()
        isScanning = false
        peripheral?.delegate = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        pairing = nil; qrPayload = nil; sas = nil; pendingSAS = nil; pendingPeer = nil
        localConfirmed = false; phoneConfirmed = false; awaitingConfirmation = false
        pairingTimeout?.cancel(); pairingTimeout = nil
        clearConnection()
        status = "Disconnected."
    }

    func forget() {
        disconnect()
        do { try ReconstructedPhoneStore.remove(); trusted = nil; pairedName = nil }
        catch { fail(error) }
    }

    func sendLinkToPhone(_ input: String) {
        guard handoffPendingID == nil else { return }
        guard isSecure, activeCompanion, handoffSupported,
              SettingsModel.shared.current.continuityHandoffToPhone else {
            handoffStatus = "Connect a supported phone and enable link handoff first."
            return
        }
        guard let url = PhoneHandoffURL.parse(input) else {
            handoffStatus = "Enter an HTTP or HTTPS link without spaces or login credentials (up to 4 KB)."
            return
        }
        let id = UUID().uuidString
        handoffPendingID = id; handoffState = "sending"; handoffStatus = "Sending link…"
        sendSecure("handoff.url", ["requestId": .string(id), "url": .string(url.absoluteString)])
        handoffTimeout?.cancel()
        handoffTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.handoffPendingID == id else { return }
            self.handoffPendingID = nil; self.handoffState = "timeout"
            self.handoffStatus = "The phone did not acknowledge the link. Check its connection before trying again."
        }
    }

    func preparePhoneDraft(kind: PhoneActionDraft.Kind, number: String, body: String = "") {
        guard phoneDraftPendingID == nil else { return }
        guard isSecure, activeCompanion, phoneDraftsSupported else {
            phoneDraftStatus = "Connect an updated Sapphire Companion to prepare phone drafts."
            return
        }
        guard let draft = PhoneActionDraft.make(kind: kind, number: number, body: body) else {
            phoneDraftStatus = "Use 7–15 ASCII digits with an optional leading +, without extensions or service codes. SMS drafts allow up to 4,000 UTF-8 bytes."
            return
        }
        let id = UUID().uuidString
        phoneDraftPendingID = id
        phoneDraftStatus = "Preparing a review notification on your phone…"
        sendSecure("phone.action.prepare", ["requestId": .string(id), "kind": .string(draft.kind.rawValue),
                                           "number": .string(draft.number), "body": .string(draft.body)])
        phoneDraftTimeout?.cancel()
        phoneDraftTimeout = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self, self.phoneDraftPendingID == id else { return }
            self.phoneDraftPendingID = nil
            self.phoneDraftStatus = "No acknowledgement. Check your phone before retrying; this does not confirm sending or calling."
        }
    }

    func sendMedia(_ action: String, seekMs: Int? = nil) {
        guard let media = ContinuityManager.shared.mediaBridge.phoneMedia,
              !media.sessionId.isEmpty else { return }
        var payload: [String: PhoneJSON] = ["action": .string(action), "sessionId": .string(media.sessionId)]
        if let seekMs { payload["seekMs"] = .number(Double(seekMs)) }
        sendSecure("media.command", payload)
    }

    private func updateClipboardMonitoring() {
        if let clipboardToken { PasteboardChangeMonitor.shared.unsubscribe(clipboardToken) }
        clipboardToken = nil
        clipboardChanges.skip(through: NSPasteboard.general.changeCount)
        guard automaticClipboard, isSecure else { return }
        clipboardToken = PasteboardChangeMonitor.shared.subscribe(interval: 0.25, priority: 10) { [weak self] change in
            guard let self, self.isSecure, self.automaticClipboard else { return }
            let board = NSPasteboard.general
            let types = Set((board.types ?? []).map(\.rawValue))
            let settings = SettingsModel.shared.settings
            let blocked = types.contains("com.sapphire.continuity.remote") || ClipboardCaptureFilter.shouldIgnore(
                types: types, sourceBundleID: board.string(forType: .sapphireSource),
                frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                ignoredBundleIDs: Set(settings.clipboardIgnoredAppBundleIDs).union(ClipboardIgnoredApps.defaultBundleIDs),
                ignoreMarkedItems: true)
            // Inspect markers before fetching text; password-manager copies stay local.
            if let text = self.clipboardChanges.consume(change: change,
                text: blocked ? nil : board.string(forType: .string), blocked: blocked) {
                self.sendSecure("clipboard.update", ["contentType": .string("text"), "text": .string(text)])
            }
        }
    }

    func copyReceivedText() {
        guard let receivedText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(receivedText, forType: .string)
        clipboardChanges.skip(through: NSPasteboard.general.changeCount)
    }

    func requestHotspot() { beginHotspotRequest(probeOnly: false) }

    private func beginHotspotRequest(probeOnly: Bool) {
        guard isSecure, !isHotspotBusy, !hotspotConnected else { return }
        if !probeOnly {
        switch hotspotLocation.authorizationStatus {
        case .notDetermined:
            hotspotNeedsLocation = true
            hotspotStatus = "Allow Location access so macOS can find the phone’s Wi-Fi network."
            hotspotLocation.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            hotspotStatus = "Allow Sapphire Location access in System Settings → Privacy & Security → Location Services, then try again."
            return
        default: break
        }
        }
        hotspotProbeOnly = probeOnly
        hotspotNeedsLocation = false
        isHotspotBusy = true; hotspotCredentialsReceived = false
        let requestID = UUID(); hotspotRequestID = requestID
        hotspotStatus = "Asking your phone to start its local hotspot…"
        sendSecure("hotspot.request")
        hotspotTask?.cancel()
        hotspotTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(35))
            guard !Task.isCancelled, let self, self.hotspotRequestID == requestID else { return }
            self.hotspotRequestID = nil; self.isHotspotBusy = false
            self.hotspotStatus = "The phone did not supply a hotspot. Enable Hotspot in Sapphire’s Android feature settings and allow Nearby Wi-Fi devices, then try again."
        }
    }

    private func acceptHotspotCredentials(_ payload: [String: PhoneJSON]) throws {
        guard let requestID = hotspotRequestID, !hotspotCredentialsReceived else { return }
        let credentials = try PhoneHotspotCredentials(payload: payload)
        let sharesInternet = payload["internet"]?.bool == true
        hotspotCredentialsReceived = true
        hotspotTask?.cancel()
        if hotspotProbeOnly {
            hotspotRequestID = nil; isHotspotBusy = false
            hotspotStatus = "Phone hotspot credentials verified. Diagnostic probe left Mac Wi-Fi unchanged."
            return
        }
        hotspotStatus = "Joining the phone’s local Wi-Fi network…"
        hotspotTask = Task { [weak self, hotspotJoiner] in
            do {
                try await hotspotJoiner.join(credentials)
                guard !Task.isCancelled, let self, self.hotspotRequestID == requestID else {
                    await hotspotJoiner.leave()
                    return
                }
                self.hotspotConnected = true
                self.hotspotStatus = sharesInternet ? "Connected to your phone’s mobile hotspot. Internet access depends on mobile data and carrier support." : "Connected to the phone’s local hotspot. This Android app does not share mobile internet."
            } catch {
                guard !Task.isCancelled, let self, self.hotspotRequestID == requestID else { return }
                // CoreWLAN errors can contain network details; do not log credentials.
                self.hotspotStatus = "Could not join the phone’s hotspot. Check Wi-Fi and Location access, then try again."
            }
            guard let self, self.hotspotRequestID == requestID else { return }
            self.hotspotRequestID = nil; self.isHotspotBusy = false
        }
    }

    private func acceptHotspotStatus(_ state: String, message: String? = nil) {
        if state == "stopped", hotspotConnected {
            hotspotConnected = false
            hotspotStatus = "The phone stopped its hotspot."
        }
        guard hotspotRequestID != nil else { return }
        switch state {
        case "starting": if !hotspotCredentialsReceived { hotspotStatus = "The phone is starting its hotspot…" }
        case "active": break // Credentials and successful Mac association are required.
        case "denied", "unsupported", "stopped", "needs_setup", "configure", "error":
            hotspotTask?.cancel(); hotspotTask = nil; hotspotRequestID = nil; isHotspotBusy = false
            if let message, !message.isEmpty { hotspotStatus = String(message.prefix(500)) }
            else { hotspotStatus = state == "unsupported" ? "This phone does not support Sapphire’s hotspot control." :
                "The phone could not start its hotspot. Check hotspot setup in your Android companion." }
        default: break
        }
    }

    func leaveHotspot() {
        guard !isHotspotBusy else { return }
        hotspotTask?.cancel(); hotspotRequestID = nil; hotspotNeedsLocation = false
        hotspotConnected = false
        if isSecure && hotspotCanStop { sendSecure("hotspot.stop") }
        hotspotStatus = hotspotCanStop ? "Disconnected. Asked the phone to stop its hotspot." : "Disconnected from the phone’s Wi-Fi. Android manages when its hotspot stops."
        Task { [hotspotJoiner] in await hotspotJoiner.leave() }
    }

    private func updateNotificationPreferences(_ preferences: PhoneNotificationPreferences) {
        let previous = appliedNotificationPreferences
        appliedNotificationPreferences = preferences
        if let previous, previous.enabled == preferences.enabled,
           previous.general == preferences.general, previous.system == preferences.system,
           previous.banners == preferences.banners {
            lastNotification = ""
            ContinuityManager.shared.notificationBridge.removeMutedApps(Set(preferences.mutedApps.keys))
            // Muting is entirely local. Allowing an app again asks for the phone's
            // current snapshot, whose entries restore quietly without old alerts.
            if Set(previous.mutedApps.keys).isSubset(of: Set(preferences.mutedApps.keys)) { return }
        }
        subscribeNotifications()
    }

    private func subscribeNotifications() {
        lastNotification = ""
        ContinuityManager.shared.notificationBridge.reset()
        guard isSecure, activeCompanion else { return }
        let preferences = PhoneNotificationPreferences(SettingsModel.shared.current)
        send("notif.subscribe", ["enabled": .bool(preferences.enabled),
            "includeGeneral": .bool(preferences.general), "includeSystem": .bool(preferences.system)])
    }

    func notificationCommand(_ entry: PhoneNotification, action: PhoneNotification.Action?, reply: String?) {
        let bridge = ContinuityManager.shared.notificationBridge
        // Closing on this Mac is immediate, even if the phone cannot acknowledge
        // the request. Enqueue the phone command before removing its local entry.
        defer {
            if action == nil && entry.clearable { bridge.dismissLocally(entry) }
        }
        guard isSecure, activeCompanion, SettingsModel.shared.current.continuityNotifications,
              bridge.contains(key: entry.key, revision: entry.revision) else { return }
        var payload: [String: PhoneJSON] = ["key": .string(entry.key), "revision": .string(entry.revision)]
        if let action {
            guard entry.actions.contains(action) else { return }
            payload["actionId"] = .string(action.id)
            if action.allowsReply {
                guard let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reply.utf8.count <= 4000 else {
                    bridge.actionStatus = "Enter a reply under 4 KB."
                    return
                }
                payload["replyText"] = .string(reply)
            }
        } else if !entry.clearable { return }
        guard let requestID = bridge.beginAction(for: entry) else { return }
        payload["requestId"] = .string(requestID)
        send(action == nil ? "notif.dismiss" : "notif.action", payload)
    }

    private func scanIfReady() {
        guard !isSleeping, wantsScan, central?.state == .poweredOn, peripheral == nil else { return }
        central?.scanForPeripherals(withServices: [Self.companionService, Self.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
        if pairing == nil { status = trusted == nil ? "Looking for Sapphire Continuity phones…" : "Looking for your paired phone…" }
        // Android may rotate its BLE address when advertising restarts. A cached
        // peripheral can wait forever; discover the current advertisement instead.
    }

    private func clearConnection() {
        writeCharacteristic = nil; subscribed = false; chunks = []; writeInFlight = false
        framing = PhoneGATTFraming(); encryption = nil; macNonce = nil; connectedID = nil
        isSecure = false; isConnecting = false
        handoffTimeout?.cancel(); handoffTimeout = nil; handoffPendingID = nil
        receivedLink = nil; receivedHandoffIDs = []; handoffSupported = false
        handoffStatus = ""; handoffState = ""
        phoneDraftTimeout?.cancel(); phoneDraftTimeout = nil; phoneDraftPendingID = nil
        phoneDraftsSupported = false; phoneDraftStatus = ""
        updateClipboardMonitoring()
        hotspotTask?.cancel(); hotspotTask = nil; hotspotRequestID = nil
        hotspotNeedsLocation = false; isHotspotBusy = false
        hotspotInternet = false; hotspotCanStop = false
        phoneStatus = PhoneDeviceStatus()
        ContinuityManager.shared.notificationBridge.reset()
        batteryPercent = nil; mediaTitle = ""; receivedText = nil; lastNotification = ""
        connectionTimeout?.cancel(); connectionTimeout = nil
        heartbeat?.cancel(); heartbeat = nil
        publishSnapshot()
    }

    // Retire the manager as well as GATT handles. CoreBluetooth can retain a
    // connection across sleep even though Android has discarded its session.
    private func retireTransport() {
        central?.delegate = nil
        central?.stopScan()
        peripheral?.delegate = nil
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        peripheral = nil
        central = nil
        peripherals.removeAll()
        nearby.removeAll()
        isScanning = false
        clearConnection()
    }

    private func prepareForSleep() {
        let shouldResume = wantsScan && reconnectAllowed
        disconnect() // Expire an unfinished pairing challenge and all timers.
        isSleeping = true
        wantsScan = shouldResume
        reconnectAllowed = shouldResume
        retireTransport()
        if shouldResume { status = "Phone connection paused while this Mac sleeps." }
    }

    private func resumeAfterWake() {
        isSleeping = false
        guard wantsScan, reconnectAllowed else { return }
        recoverTransport("Reconnecting to your phone after wake…")
    }

    private func recoverTransport(_ message: String) {
        guard pairing == nil, reconnectAllowed else { disconnect(); return }
        recoveryTask?.cancel()
        retireTransport()
        status = message
        // Give the radio time to return after wake or a failed GATT connection.
        // poweredOn then starts a fresh scan; a later power-on does the same.
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, !self.isSleeping,
                  self.wantsScan, self.reconnectAllowed else { return }
            self.recoveryTask = nil
            self.start()
        }
    }

    private func armTimeout() {
        connectionTimeout?.cancel()
        connectionTimeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard !Task.isCancelled, let self, !self.isSecure, self.pairing == nil else { return }
            self.lastError = "The phone did not finish connecting. Keep Sapphire open on the phone."
            self.recoverTransport("Retrying the phone connection…")
        }
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        logger.error("Phone protocol operation failed: \(error.localizedDescription, privacy: .public)")
    }

    private func hello() {
        var payload: [String: PhoneJSON] = ["deviceId": .string(macID), "deviceName": .string(macName),
            "deviceType": .string("mac"), "protocolVersion": .number(1),
            "capabilities": .array(["clipboard", "media", "status", "notifications", "hotspot"].map(PhoneJSON.string)),
            "appVersion": .string("local-reconstruction-1")]
        if trusted != nil && pairing == nil {
            if macNonce == nil { macNonce = PhonePairingSession.randomBytes(32) }
            payload["bleEncryption"] = .object(["version": .number(1), "nonce": .string(macNonce!.base64EncodedString())])
        }
        send("hello", payload, plaintext: true)
    }

    private func sendSecure(_ type: String, _ payload: [String: PhoneJSON] = [:]) {
        guard isSecure else { lastError = "Connect and confirm your phone first."; return }
        send(type, payload)
    }

    private func send(_ type: String, _ payload: [String: PhoneJSON] = [:], plaintext: Bool = false) {
        guard let peripheral, let writeCharacteristic, subscribed else { return }
        do {
            let key = "reconstructedContinuity.outgoingCounter.v1"
            let next = max(UserDefaults.standard.object(forKey: key) as? Int64 ?? 0, 0) + 1
            UserDefaults.standard.set(next, forKey: key)
            let envelope = PhoneEnvelope(type: type, counter: next, payload: payload)
            var data = try JSONEncoder().encode(envelope)
            if !plaintext {
                guard encryption != nil else { throw PhoneWireError.unauthenticated }
                data = try encryption!.seal(data)
            }
            let outgoing = try PhoneGATTFraming.chunks(data, id: messageID,
                maximumWrite: peripheral.maximumWriteValueLength(for: .withResponse))
            guard chunks.count + outgoing.count <= 512 else { throw PhoneWireError.oversized }
            messageID &+= 1
            chunks.append(contentsOf: outgoing)
            logger.info("Send \(type, privacy: .public) (\(data.count) bytes)")
            drain(peripheral, writeCharacteristic)
        } catch { fail(error) }
    }

    private func drain(_ peripheral: CBPeripheral, _ characteristic: CBCharacteristic) {
        guard !writeInFlight, !chunks.isEmpty else { return }
        writeInFlight = true
        peripheral.writeValue(chunks.removeFirst(), for: characteristic, type: .withResponse)
    }

    private func received(_ data: Data) throws {
        let encrypted = data.starts(with: Data("SBE1".utf8))
        let message: Data
        if encrypted {
            guard encryption != nil else { throw PhoneWireError.unauthenticated }
            message = try encryption!.open(data)
        } else { message = data }
        let envelope = try JSONDecoder().decode(PhoneEnvelope.self, from: message)
        lastMessageType = envelope.type
        guard envelope.v == 1 else { throw PhoneWireError.malformed }
        if !encrypted {
            guard PhoneHandshakePolicy.acceptsPlaintext(type: envelope.type, isSecure: isSecure) else { return }
        }
        lastReceived = Date()
        logger.info("Receive \(envelope.type, privacy: .public) (\(data.count) bytes)")
        let p = envelope.payload
        switch envelope.type {
        case "pair.hello":
            guard let pairing else { return }
            guard let peripheral,
                  let id = p["deviceId"]?.string, !id.isEmpty,
                  let publicString = p["ecdhPublicKey"]?.string, let publicKey = Data(base64Encoded: publicString),
                  let nonceString = p["nonce"]?.string, let nonce = Data(base64Encoded: nonceString) else { throw PhoneWireError.malformed }
            let secrets = try pairing.derive(publicKey: publicKey, phoneNonce: nonce)
            if let pendingPeer {
                guard pendingPeer.id == id, pendingPeer.publicKey == publicKey,
                      pendingPeer.linkKey == secrets.linkKey else { throw PhoneWireError.unauthenticated }
                return // Android retries the same hello while the user compares the codes.
            }
            pendingPeer = ReconstructedPhoneRecord(id: id, name: p["deviceName"]?.string ?? "Android Phone",
                peripheralID: peripheral.identifier, publicKey: publicKey, linkKey: secrets.linkKey)
            pendingSAS = secrets.sas; sas = secrets.sas; awaitingConfirmation = true
            qrPayload = nil
            status = "Compare this code with your phone. Confirm on both devices only if it matches."
        case "pair.confirm":
            guard pairing != nil else { return }
            guard let pendingSAS, p["sas"]?.string == pendingSAS else { throw PhoneWireError.unauthenticated }
            phoneConfirmed = true
            finishPairingIfConfirmed()
        case "hello":
            guard pairing == nil else { return }
            guard let trusted, p["deviceId"]?.string == trusted.id,
                  let remote = p["bleEncryption"]?.object, remote["version"]?.int == 1,
                  let encoded = remote["nonce"]?.string, let nonce = Data(base64Encoded: encoded),
                  let macNonce else { throw PhoneWireError.unauthenticated }
            encryption = try PhoneBLESession(linkKey: trusted.linkKey, macNonce: macNonce, phoneNonce: nonce)
            connectedID = trusted.id
            // A plaintext hello is not proof of possession. Wait for an authenticated response.
            status = "Verifying the encrypted phone connection…"
            send("status.request")
            send("media.request")
            startHeartbeat()
        case "status.device", "battery.state":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            batteryPercent = p["batteryPercent"]?.int.flatMap { (0...100).contains($0) ? $0 : nil }
            if envelope.type == "status.device" {
                phoneStatus = PhoneDeviceStatus(payload: p)
                hotspotInternet = p["hotspotMode"]?.string == "internet"
                hotspotCanStop = p["hotspotStopSupported"]?.bool == true
                handoffSupported = p["handoffSupported"]?.bool == true
                phoneDraftsSupported = p["phoneActionDraftsSupported"]?.bool == true
            }
        case "media.state":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            mediaTitle = p["title"]?.string ?? ""
            if let media = try? JSONDecoder().decode(ContinuityMediaState.self, from: JSONEncoder().encode(p)) {
                ContinuityManager.shared.acceptReconstructedMedia(media, deviceName: trusted?.name)
            }
        case "handoff.url":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            guard let id = p["requestId"]?.string, !id.isEmpty, id.utf8.count <= 128,
                  let raw = p["url"]?.string, let url = PhoneHandoffURL.parse(raw) else { break }
            if !receivedHandoffIDs.contains(id) {
                receivedHandoffIDs.append(id)
                if receivedHandoffIDs.count > 32 { receivedHandoffIDs.removeFirst() }
                receivedLink = url
                handoffStatus = "Link received from your phone. Review it below before opening."
            }
            send("handoff.result", ["requestId": .string(id), "state": .string("received")])
        case "handoff.result":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            guard p["requestId"]?.string == handoffPendingID, handoffPendingID != nil else { break }
            handoffTimeout?.cancel(); handoffTimeout = nil; handoffPendingID = nil
            let state = p["state"]?.string ?? "error"
            handoffState = ["ready", "disabled", "needs_permission"].contains(state) ? state : "error"
            switch handoffState {
            case "ready": handoffStatus = "Link sent. Tap the Sapphire notification on your phone to review and open it."
            case "disabled": handoffStatus = "Enable Receive web links from paired Mac in Sapphire Companion."
            case "needs_permission": handoffStatus = "Allow Sapphire notifications and its Links from Mac channel on your phone."
            default: handoffStatus = "The phone could not receive this link. Check its connection and try again."
            }
        case "phone.action.result":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            guard let pending = phoneDraftPendingID, p["requestId"]?.string == pending else { break }
            phoneDraftTimeout?.cancel(); phoneDraftTimeout = nil; phoneDraftPendingID = nil
            switch p["state"]?.string {
            case "ready": phoneDraftStatus = "Draft ready for review on your phone for two minutes. Nothing has been sent or called."
            case "disabled": phoneDraftStatus = "Enable Receive SMS and dialer drafts in Sapphire Companion."
            case "needs_permission": phoneDraftStatus = "Allow Sapphire notifications and its Phone drafts from Mac channel."
            case "expired": phoneDraftStatus = "That draft expired or was replaced. Prepare a new draft if needed."
            default: phoneDraftStatus = "The phone could not prepare this draft. Nothing has been sent or called."
            }
        case "clipboard.update":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            if p["contentType"]?.string == "text" { receivedText = p["text"]?.string }
        case "hotspot.credentials":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            try acceptHotspotCredentials(p)
        case "hotspot.status":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            acceptHotspotStatus(p["state"]?.string ?? "", message: p["message"]?.string)
        case "notif.posted", "notif.postedV2":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            let preferences = PhoneNotificationPreferences(SettingsModel.shared.current)
            if preferences.enabled, let entry = PhoneNotification(payload: p),
               (!entry.isGeneral || preferences.general), (!entry.isSystem || preferences.system),
               preferences.mutedApps[entry.appId] == nil {
                lastNotification = [entry.appName, entry.title, entry.text].filter { !$0.isEmpty }.joined(separator: " — ")
                ContinuityManager.shared.notificationBridge.accept(entry)
            }
        case "notif.removed":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            if let key = p["key"]?.string, let revision = p["revision"]?.string {
                ContinuityManager.shared.notificationBridge.remove(key: key, revision: revision)
            }
        case "notif.reset":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            lastNotification = ""
            ContinuityManager.shared.notificationBridge.reset()
        case "notif.actionResult":
            guard encrypted else { throw PhoneWireError.unauthenticated }
            if let requestID = p["requestId"]?.string {
                ContinuityManager.shared.notificationBridge.finishAction(requestID: requestID,
                    message: p["message"]?.string.map { String($0.prefix(256)) } ?? "Phone action completed.")
            }
        case "ping": send("pong", p)
        case "pair.classicStart":
            send("pair.classicDecline", ["reason": .string("Use QR pairing in this local build.")], plaintext: true)
        default: break
        }
        if encrypted {
            if let trusted, let peripheral, trusted.peripheralID != peripheral.identifier {
                let refreshed = ReconstructedPhoneRecord(id: trusted.id, name: trusted.name,
                    peripheralID: peripheral.identifier, publicKey: trusted.publicKey, linkKey: trusted.linkKey)
                // Only an authenticated frame permits updating the persisted address.
                try ReconstructedPhoneStore.save(refreshed)
                self.trusted = refreshed
            }
            let justConnected = !isSecure
            isSecure = true; isConnecting = false
            if justConnected { lastError = nil; updateClipboardMonitoring(); subscribeNotifications() }
            status = "Connected securely over Bluetooth."
            connectionTimeout?.cancel(); connectionTimeout = nil
            publishSnapshot()
        }
    }

    private func finishPairingIfConfirmed() {
        guard localConfirmed, phoneConfirmed, let pendingPeer, let pairing,
              Date() < pairing.expiresAt else { return }
        do { try ReconstructedPhoneStore.save(pendingPeer) }
        catch { fail(error); return }
        trusted = pendingPeer; pairedName = pendingPeer.name
        SettingsModel.shared.settings.continuityEnabled = true
        send("pair.result", ["ok": .bool(true), "spkiSha256": .string("")], plaintext: true)
        self.pairing = nil; self.pendingPeer = nil; pendingSAS = nil
        pairingTimeout?.cancel(); pairingTimeout = nil
        sas = nil; awaitingConfirmation = false; qrPayload = nil
        status = "Paired. Starting an encrypted session…"
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, self.peripheral != nil, !Task.isCancelled else { return }
            self.hello(); self.armTimeout()
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, let self else { return }
                if Date().timeIntervalSince(self.lastReceived) > 65 {
                    self.lastError = "The phone stopped responding. Reopening its Bluetooth connection…"
                    self.recoverTransport("Reconnecting to your phone…")
                    return
                }
                self.send("status.request")
            }
        }
    }

    private func publishSnapshot() {
        let snapshot = ContinuityConnectivitySnapshot(severity: isSecure ? .healthy : (trusted == nil ? .noDevice : .offline),
            deviceName: trusted?.name ?? "", linkState: isSecure ? .connected : .offline,
            headline: isSecure ? "Phone connected" : "Phone disconnected", detail: "Local Bluetooth reconstruction",
            phoneBatteryPercent: batteryPercent, phoneCharging: phoneStatus.charging,
            phoneNetwork: phoneStatus.network.flatMap(ContinuityNetworkKind.init(rawValue:)),
            phoneSignalLevel: phoneStatus.signalLevel, phoneCarrier: phoneStatus.carrier)
        ContinuityManager.shared.acceptReconstructedConnection(snapshot,
            record: isSecure ? trusted.map { ContinuityPairedPeer(id: $0.id, name: $0.name, deviceType: .phone) } : nil)
    }
}

extension ReconstructedPhoneLink: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central === self.central, !isSleeping else { return }
        switch central.state {
        case .poweredOn: scanIfReady()
        case .unauthorized: status = "Allow Bluetooth access for Sapphire in System Settings → Privacy & Security → Bluetooth."
        case .poweredOff: status = "Turn on Bluetooth on this Mac."
        case .unsupported: status = "Bluetooth Low Energy is unavailable on this Mac."
        default: status = "Waiting for Bluetooth…"
        }
        if central.state != .poweredOn {
            isScanning = false
            if let peripheral { central.cancelPeripheralConnection(peripheral) }
            peripheral = nil
            clearConnection()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard central === self.central, !isSleeping, wantsScan else { return }
        peripherals[peripheral.identifier] = peripheral
        let advertisement = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data).flatMap(PhoneAdvertisement.init)
        let isCompanion = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(Self.companionService) == true
        let item = NearbyPhone(id: peripheral.identifier,
            name: isCompanion ? "Sapphire Companion" : (advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Sapphire Android Phone"),
            rssi: RSSI.intValue, advertisement: advertisement, lastSeen: Date(), isCompanion: isCompanion)
        nearby.removeAll { $0.id == item.id || Date().timeIntervalSince($0.lastSeen) > 30 }
        nearby.append(item)
        nearby.sort { $0.rssi > $1.rssi }
        if pairing == nil, let trusted, advertisement?.matches(deviceID: trusted.id) == true {
            connect(item.id)
        } else if pairing != nil, self.peripheral == nil, advertisement?.isPairing == true,
                  nearby.filter({ $0.advertisement?.isPairing == true }).count == 1 {
            // Establish only the transport. Both users must still compare and confirm
            // the QR-derived SAS before any key is persisted or features are enabled.
            connect(item.id)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard central === self.central, peripheral === self.peripheral else { return }
        status = "Discovering phone services…"
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard central === self.central, peripheral === self.peripheral else { return }
        self.peripheral = nil; clearConnection()
        status = "Could not connect. Keep the phone unlocked and try again."
        if let error { fail(error) }
        recoverTransport("Retrying the phone connection…")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard central === self.central, peripheral === self.peripheral else { return }
        self.peripheral = nil; clearConnection()
        status = "The phone disconnected."
        if let error { fail(error) }
        if reconnectAllowed && pairing == nil { recoverTransport("Reconnecting to your phone…") }
    }
}

extension ReconstructedPhoneLink: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        guard peripheral === self.peripheral,
              invalidatedServices.contains(where: { $0.uuid == serviceUUID }) else { return }
        recoverTransport("The phone restarted its Bluetooth service. Reconnecting…")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        if let error { fail(error); recoverTransport("Reopening the phone connection…"); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            fail(PhoneWireError.malformed); recoverTransport("Reopening the phone connection…"); return
        }
        peripheral.discoverCharacteristics([inboxUUID, outboxUUID, controlUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if let error { fail(error); recoverTransport("Reopening the phone connection…"); return }
        guard let characteristics = service.characteristics,
              let inbox = characteristics.first(where: { $0.uuid == inboxUUID }),
              let outbox = characteristics.first(where: { $0.uuid == outboxUUID }) else {
            fail(PhoneWireError.malformed); recoverTransport("Reopening the phone connection…"); return
        }
        writeCharacteristic = inbox
        peripheral.setNotifyValue(true, for: outbox)
        status = "Setting up Bluetooth. Accept any system pairing prompt on both devices."
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if let error { fail(error); recoverTransport("Reopening the phone connection…"); return }
        guard characteristic.uuid == outboxUUID, characteristic.isNotifying else { return }
        subscribed = true
        status = pairing == nil ? "Authenticating your phone…" : "Connected. Scan the code with Sapphire on your phone."
        hello()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if let error { fail(error); return }
        guard characteristic.uuid == outboxUUID || characteristic.uuid == controlUUID,
              let value = characteristic.value else { return }
        do { if let data = try framing.receive(value) { try received(data) } }
        catch { fail(error); disconnect() }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        writeInFlight = false
        if let error { fail(error); recoverTransport("Reopening the phone connection…"); return }
        if let writeCharacteristic { drain(peripheral, writeCharacteristic) }
    }
}
#endif

#if !SAPPHIRE_FULL_BUILD
extension ReconstructedPhoneLink: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard hotspotNeedsLocation else { return }
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            hotspotNeedsLocation = false
            requestHotspot()
        case .denied, .restricted:
            hotspotNeedsLocation = false
            hotspotStatus = "Location access is required by macOS to find the phone’s hotspot."
        default: break
        }
    }
}
#endif
