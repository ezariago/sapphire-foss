#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import CryptoKit

@MainActor
final class SmartInboxMonitor: ObservableObject {
    static let shared = SmartInboxMonitor()
    @Published private(set) var latestOTP: OTPEvent?
    @Published private(set) var activeParcels: [ParcelShipment] = []
    private struct Configuration: Equatable { let enabled: Bool; let parcels: Bool }
    private var configuration = Configuration(enabled: false, parcels: false)
    private var started = false
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lockObserver: NSObjectProtocol?
    private var seen: [String] = []
    private var expiries: [String: TimeInterval] = [:]
    private var presented = Set<String>()
    private var parcelOrigins: [String: String] = [:]
    private var otpOrigin = ""
    private var lastClock: TimeInterval?
    private var consumed: [(String, TimeInterval)] = []
    private let copyGate = SmartInboxCopyGate()
    private let clock: @Sendable () -> TimeInterval
    private let sessionLocked: @Sendable () -> Bool
    private let automaticMaintenance: Bool
    private let pasteboardCount: () -> Int
    private nonisolated static func sessionIsLocked() -> Bool {
        guard let state = CGSessionCopyCurrentDictionary() as? [String: Any], state[kCGSessionOnConsoleKey as String] as? Bool == true else { return true }
        return state["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
    init(clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, automaticMaintenance: Bool = true,
         sessionLocked: @escaping @Sendable () -> Bool = { SmartInboxMonitor.sessionIsLocked() },
         pasteboardCount: @escaping () -> Int = { NSPasteboard.general.changeCount }) {
        self.clock = clock; self.sessionLocked = sessionLocked; self.automaticMaintenance = automaticMaintenance; self.pasteboardCount = pasteboardCount
    }
    func start() {
        guard !started else { return }; started = true
        subscription = SettingsModel.shared.$settings
            .map { Configuration(enabled: $0.smartInboxEnabled && $0.masterNotificationsEnabled, parcels: $0.parcelTrackingEnabled) }
            .removeDuplicates().sink { [weak self] in self?.configure($0) }
        if automaticMaintenance {
            timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.expire() } }
            observers = [NSWorkspace.willSleepNotification].map { name in
                NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.clear() } }
            }
            lockObserver = DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.clear() } }
        }
    }
    func stop() {
        started = false; subscription = nil; timer?.invalidate(); timer = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }; lockObserver = nil
        SmartInboxInputGate.shared.configure(false); clear()
    }
    private func configure(_ value: Configuration) {
        guard started else { return }
        configuration = value
        SmartInboxInputGate.shared.configure(value.enabled)
        clear()
    }
    func clear() {
        latestOTP = nil; activeParcels = []; seen = []; expiries = [:]; presented = []; parcelOrigins = [:]; consumed = []; otpOrigin = ""
        copyGate.clear(); lastClock = nil
        SmartInboxInputGate.shared.configure(started && configuration.enabled)
    }
    func expire() {
        guard !sessionLocked() else { clear(); return }
        let now = clock()
        guard now.isFinite, now >= 0, lastClock.map({ now >= $0 }) ?? true else { clear(); return }
        lastClock = now
        let expired = Set(expiries.filter { !$0.value.isFinite || $0.value <= now }.map(\.key))
        if let event = latestOTP, expired.contains(event.id) { latestOTP = nil; otpOrigin = "" }
        activeParcels.removeAll { expired.contains($0.id) }
        for id in expired { expiries.removeValue(forKey: id); presented.remove(id); parcelOrigins.removeValue(forKey: id); copyGate.remove(id) }
        consumed.removeAll { $0.1 <= now }
    }
    func ingestNotification(id: String, source: String, title: String, body: String, date: Date, now: Date = Date(), ticket: UInt64? = nil) {
        guard started, configuration.enabled, !sessionLocked(), ticket.map({ SmartInboxInputGate.shared.accepts($0) }) ?? true,
              !id.isEmpty, id.utf8.count <= 2048, source.utf8.count <= 256,
              let age = SmartInboxPolicy.age(of: date, now: now) else { return }
        let text = source + " " + title + " " + body
        guard text.utf8.count <= SmartInboxPolicy.maxInputBytes, !seen.contains(id), clock().isFinite, clock() >= 0 else { return }
        expire()
        guard !sessionLocked(), ticket.map({ SmartInboxInputGate.shared.accepts($0) }) ?? true else { return }
        seen.append(id); seen = Array(seen.suffix(256))
        if age <= 300, !(latestOTP.map { $0.date > date } ?? false), let code = VerificationCodeDetector.find(in: text) {
            if let old = latestOTP { expiries.removeValue(forKey: old.id); copyGate.remove(old.id); presented.remove(old.id) }
            let event = OTPEvent(id: UUID().uuidString, code: code, source: source, title: "Detected code", body: "", date: date)
            latestOTP = event; otpOrigin = id
            expiries[event.id] = clock() + (300 - age); copyGate.put(event.id, from: clock(), until: expiries[event.id]!)
        }
        if configuration.parcels {
            for (carrier, number) in SmartInboxPolicy.parcelReferences(in: text) {
                if activeParcels.contains(where: { $0.carrier == carrier && $0.trackingNumber == number }) { continue }
                let parcel = ParcelShipment(id: UUID().uuidString, trackingNumber: number, carrier: carrier,
                    title: "Detected tracking reference", status: "Unverified", detail: "Status not fetched. Open the carrier site to look it up.",
                    lastUpdated: date, sourceEmailSubject: nil, isDelivered: false)
                activeParcels.insert(parcel, at: 0); parcelOrigins[parcel.id] = id
                expiries[parcel.id] = clock() + (86400 - age); copyGate.put(parcel.id, from: clock(), until: expiries[parcel.id]!)
                if age > 300 { presented.insert(parcel.id) }
            }
            while activeParcels.count > 30 { if let old = activeParcels.last { removeParcel(old.id) } }
        }
    }
    func presentOTP(code: String, source: String, title: String, body: String) {
        guard VerificationCodeDetector.find(in: title + " " + body) == code else { return }
        ingestNotification(id: "direct:" + UUID().uuidString, source: source, title: title, body: body, date: Date())
    }
    func consumeOTP(_ code: String) {
        let key = SHA256.hash(data: Data(code.utf8)).map { String(format: "%02x", $0) }.joined()
        expire(); consumed.removeAll { $0.0 == key }; consumed.append((key, clock() + 300)); consumed = Array(consumed.suffix(128))
        if let event = latestOTP, event.code == code { presented.insert(event.id) }
    }
    func hasConsumedOTP(_ code: String) -> Bool { expire(); let key = SHA256.hash(data: Data(code.utf8)).map { String(format: "%02x", $0) }.joined(); return consumed.contains { $0.0 == key } }
    func dismissOTP() { if let event = latestOTP { consumeOTP(event.code); copyGate.remove(event.id); expiries.removeValue(forKey: event.id) }; latestOTP = nil; otpOrigin = "" }
    func otpForPresentation(keepingCurrent: Bool) -> OTPEvent? {
        expire(); guard started, configuration.enabled, let event = latestOTP, keepingCurrent || !presented.contains(event.id) else { return nil }
        if !keepingCurrent {
            let key = SHA256.hash(data: Data(event.code.utf8)).map { String(format: "%02x", $0) }.joined()
            guard !consumed.contains(where: { $0.0 == key }) else { return nil }
        }
        presented.insert(event.id); return event
    }
    func parcelForPresentation(currentID: String? = nil) -> ParcelShipment? {
        expire(); guard started, configuration.enabled, let parcel = activeParcels.first(where: { $0.id == currentID }) ?? activeParcels.first(where: { !presented.contains($0.id) }) else { return nil }
        presented.insert(parcel.id); return parcel
    }
    func removeParcel(_ id: String) { activeParcels.removeAll { $0.id == id }; expiries.removeValue(forKey: id); parcelOrigins.removeValue(forKey: id); presented.remove(id); copyGate.remove(id) }
    func removePhoneItems() {
        if otpOrigin.hasPrefix("phone:") { dismissOTP() }
        for id in parcelOrigins.filter({ $0.value.hasPrefix("phone:") }).map(\.key) { removeParcel(id) }
    }
    func copyOTP(_ event: OTPEvent, completion: @escaping (Bool) -> Void) {
        expire(); guard latestOTP?.id == event.id else { completion(false); return }
        copy(event.code, id: event.id) { [weak self] success in if success { self?.consumeOTP(event.code) }; completion(success) }
    }
    func copyParcel(_ parcel: ParcelShipment, completion: @escaping (Bool) -> Void) {
        expire(); guard activeParcels.contains(where: { $0.id == parcel.id }) else { completion(false); return }
        copy(parcel.trackingNumber, id: parcel.id, completion: completion)
    }
    private func copy(_ text: String, id: String, completion: @escaping (Bool) -> Void) {
        let gate = copyGate, clock = clock, locked = sessionLocked, expected = pasteboardCount()
        PasteboardLane.shared.write({ pasteboard in
            guard !locked(), gate.allows(id, now: clock()), pasteboard.changeCount == expected else { return false }
            let item = NSPasteboardItem(); item.setString(text, forType: .string); item.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
            pasteboard.clearContents(); return pasteboard.writeObjects([item])
        }, completion: { completion($0 != nil) })
    }
}
#endif
