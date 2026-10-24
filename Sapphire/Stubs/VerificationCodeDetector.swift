// Public, conservative notification-code heuristic; not a Mail reader.
#if !SAPPHIRE_FULL_BUILD
import Foundation

enum VerificationCodeDetector {
    private static let tokens = try! NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])(?:[0-9]{4,8}|[A-Za-z0-9]{6,8})(?![A-Za-z0-9_])"#)
    private static let context = try! NSRegularExpression(pattern: #"(?i)\b(?:otp|one[- ]time|verification|passcode|security code|authentication|login code|sign[- ]in code|kode verifikasi|kode otp)\b|\b(?:your|use|enter)\b.{0,20}\bcode\b|\bcode\s*(?:is|:)"#)
    static func find(in text: String) -> String? {
        guard text.utf8.count <= 8192 else { return nil }
        let full = NSRange(text.startIndex..., in: text)
        let contexts = context.matches(in: text, range: full)
        guard !contexts.isEmpty else { return nil }
        let value = text as NSString
        var candidates: [(String, Int)] = []
        for match in tokens.matches(in: text, range: full) {
            let token = value.substring(with: match.range)
            guard token.utf8.contains(where: { (48...57).contains($0) }) else { continue }
            let start = match.range.location, end = NSMaxRange(match.range)
            func digit(_ position: Int) -> Bool { position >= 0 && position < value.length && (48...57).contains(value.character(at: position)) }
            // Exclude date fragments, monetary amounts and whitespace-grouped numbers.
            if start > 0 && [UInt16(36), 163, 165, 8364].contains(value.character(at: start - 1)) { continue }
            if start > 1 && [UInt16(45), 47, 46].contains(value.character(at: start - 1)) && digit(start - 2) { continue }
            if end + 1 < value.length && [UInt16(45), 47, 46].contains(value.character(at: end)) && digit(end + 1) { continue }
            if end + 1 < value.length && value.character(at: end) == 32 && digit(end + 1) { continue }
            if start > 1 && value.character(at: start - 1) == 32 && digit(start - 2) { continue }
            let distance = contexts.map { context -> Int in
                if NSMaxRange(context.range) <= start { return start - NSMaxRange(context.range) }
                if end <= context.range.location { return context.range.location - end }
                return 0
            }.min() ?? Int.max
            if distance <= 48 { candidates.append((token, distance)) }
        }
        let best = Set(candidates.map(\.0))
        return best.count == 1 ? best.first : nil
    }
}
#endif
