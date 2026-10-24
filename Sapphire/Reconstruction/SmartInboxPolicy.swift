#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Producer tickets reject work queued before disable/re-enable or stop/start.
final class SmartInboxInputGate: @unchecked Sendable {
    static let shared = SmartInboxInputGate()
    private let lock = NSLock()
    private var enabled = false
    private var generation: UInt64 = 0
    func configure(_ value: Bool) { lock.withLock { enabled = value; generation &+= 1 } }
    func capture() -> UInt64? { lock.withLock { enabled ? generation : nil } }
    func accepts(_ ticket: UInt64) -> Bool { lock.withLock { enabled && generation == ticket } }
}

final class SmartInboxCopyGate: @unchecked Sendable {
    private let lock = NSLock()
    private var expiries: [String: (TimeInterval, TimeInterval)] = [:]
    func put(_ id: String, from: TimeInterval, until: TimeInterval) { lock.withLock { expiries[id] = (from, until) } }
    func remove(_ id: String) { _ = lock.withLock { expiries.removeValue(forKey: id) } }
    func clear() { lock.withLock { expiries.removeAll() } }
    func allows(_ id: String, now: TimeInterval) -> Bool {
        lock.withLock { now.isFinite && (expiries[id].map { $0.0.isFinite && $0.1.isFinite && now >= $0.0 && now < $0.1 } ?? false) }
    }
}

enum SmartInboxPolicy {
    static let maxInputBytes = 8192
    static func age(of date: Date, now: Date) -> TimeInterval? {
        let age = now.timeIntervalSince(date)
        return age.isFinite && age >= 0 && age <= 86400 ? age : nil
    }
    static func parcelReferences(in text: String) -> [(ParcelCarrier, String)] {
        guard text.utf8.count <= maxInputBytes else { return [] }
        let text = text.uppercased()
        let patterns: [(ParcelCarrier, String, String)] = [
            (.ups, #"\bUPS\b"#, #"(?<![A-Z0-9])1Z[A-Z0-9]{16}(?![A-Z0-9])"#),
            (.fedex, #"\bFEDEX\b"#, #"(?<![A-Z0-9])(?:[0-9]{15}|[0-9]{12})(?![A-Z0-9])"#),
            (.usps, #"\bUSPS\b"#, #"(?<![A-Z0-9])(?:[0-9]{22}|[0-9]{20}|[A-Z]{2}[0-9]{9}[A-Z]{2})(?![A-Z0-9])"#),
            (.dhl, #"\bDHL\b"#, #"(?<![A-Z0-9])[0-9]{10}(?![A-Z0-9])"#)
        ]
        var result: [(ParcelCarrier, String)] = []
        for (carrier, hint, pattern) in patterns {
            guard text.range(of: hint, options: .regularExpression) != nil,
                  let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).prefix(4) {
                guard let range = Range(match.range, in: text) else { continue }
                let number = String(text[range])
                if !result.contains(where: { $0.0 == carrier && $0.1 == number }) { result.append((carrier, number)) }
            }
        }
        return Array(result.prefix(4))
    }
    static func carrierURL(_ carrier: ParcelCarrier, number: String) -> URL? {
        // Open official landing pages only. No identifier is sent until the user
        // explicitly chooses to enter/paste it on that carrier's site.
        guard parcelReferences(in: carrier.displayName + " " + number).contains(where: { $0.0 == carrier && $0.1 == number.uppercased() }) else { return nil }
        switch carrier {
        case .ups: return URL(string: "https://www.ups.com/track")
        case .fedex: return URL(string: "https://www.fedex.com/en-us/tracking.html")
        case .usps: return URL(string: "https://tools.usps.com/go/TrackConfirmAction")
        case .dhl: return URL(string: "https://www.dhl.com/global-en/home/tracking.html")
        case .amazon, .unknown: return nil
        }
    }
}
#endif
