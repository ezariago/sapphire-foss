#if !SAPPHIRE_FULL_BUILD
import Foundation

enum ClipboardURLCleaner {
    private static let tracking: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "_hsenc", "_hsmi", "mkt_tok", "vero_id"]
    static func clean(_ text: String, customParameters: [String] = []) -> String {
        guard text.utf8.count <= 1_000_000, text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              var url = URLComponents(string: text), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty,
              let query = url.percentEncodedQuery, !query.isEmpty else { return text }
        let pieces = query.components(separatedBy: "&")
        func key(_ piece: String) -> String {
            String(piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0]).removingPercentEncoding?.lowercased() ?? ""
        }
        // Do not invalidate a signed download/authentication URL.
        let signatures: Set<String> = ["signature", "sig", "x-amz-signature", "x-goog-signature", "oauth_signature"]
        guard !pieces.contains(where: { signatures.contains(key($0)) }) else { return text }
        let custom = Set(customParameters.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let kept = pieces.filter { piece in
            let name = key(piece)
            return !name.hasPrefix("utm_") && !tracking.contains(name) && !custom.contains(name)
        }
        guard kept.count != pieces.count else { return text }
        url.percentEncodedQuery = kept.isEmpty ? nil : kept.joined(separator: "&")
        return url.string ?? text
    }
}

struct ClipboardExpiryPolicy {
    private(set) var changeCount: Int
    private(set) var copiedAt: TimeInterval
    init(changeCount: Int, now: TimeInterval) { self.changeCount = changeCount; copiedAt = now }
    mutating func observe(_ count: Int, now: TimeInterval) {
        if count != changeCount { changeCount = count; copiedAt = now }
    }
    func shouldClear(now: TimeInterval, interval: TimeInterval) -> Bool {
        interval.isFinite && interval > 0 && now >= copiedAt && now - copiedAt >= interval
    }
}
#endif
