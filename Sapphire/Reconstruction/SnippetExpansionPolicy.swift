#if !SAPPHIRE_FULL_BUILD
import Foundation

struct SnippetInputGate {
    struct Ticket: Equatable { var generation: UInt64; var pid: Int32 }
    private var generation: UInt64 = 0
    private var enabled = false
    private var pid: Int32?
    private var pendingKey: Int64?
    mutating func invalidate() { generation &+= 1; pendingKey = nil }
    mutating func configure(enabled: Bool) { self.enabled = enabled; invalidate() }
    mutating func foreground(_ pid: Int32?) { self.pid = pid; invalidate() }
    mutating func down(_ key: Int64, eligible: Bool, target: Int64 = 0) {
        invalidate()
        if enabled, let pid, eligible, target == 0 || target == Int64(pid) { pendingKey = key }
    }
    mutating func up(_ key: Int64, eligible: Bool, target: Int64 = 0) -> Ticket? {
        let matches = pendingKey == key
        invalidate()
        guard enabled, let pid, matches, eligible, target == 0 || target == Int64(pid) else { return nil }
        return Ticket(generation: generation, pid: pid)
    }
    func isCurrent(_ ticket: Ticket) -> Bool { enabled && ticket.generation == generation && ticket.pid == pid }
}

enum SnippetExpansionPolicy {
    struct Rule: Equatable {
        var trigger: String
        var replacement: String
        var enabled = true
    }
    struct Match: Equatable {
        var range: NSRange
        var template: String
        var suffix: String
    }
    static func validTrigger(_ trigger: String) -> Bool {
        (2...64).contains(trigger.utf16.count)
            && !trigger.unicodeScalars.contains { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }
    }
    static func match(text: String, selection: NSRange, rules: [Rule], afterDelimiter: Bool) -> Match? {
        let source = text as NSString
        guard source.length <= 1_000_000, selection.length == 0, selection.location >= 0, selection.location <= source.length,
              selection.location != NSNotFound, Range(selection, in: text) != nil else { return nil }
        let caret = Range(selection, in: text)!.lowerBound
        if !afterDelimiter, let next = text[caret...].first,
           !next.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) }) { return nil }
        let prefix = String(text[..<caret])
        var body = prefix
        var suffix = ""
        if afterDelimiter {
            guard let last = body.last, last.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) }) else { return nil }
            suffix = String(body.removeLast())
        }
        // Longest match first; duplicate triggers deterministically use the first enabled rule.
        guard rules.count <= 1000 else { return nil }
        let candidates = rules.enumerated().filter { $0.element.enabled && validTrigger($0.element.trigger) && $0.element.replacement.utf16.count <= 16_384 }
            .sorted { lhs, rhs in lhs.element.trigger.utf16.count == rhs.element.trigger.utf16.count ? lhs.offset < rhs.offset : lhs.element.trigger.utf16.count > rhs.element.trigger.utf16.count }
        for (_, rule) in candidates where body.hasSuffix(rule.trigger) {
            let before = body.dropLast(rule.trigger.count)
            if let last = before.last, !last.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) }) { continue }
            let length = rule.trigger.utf16.count + suffix.utf16.count
            let range = NSRange(location: selection.location - length, length: length)
            guard Range(range, in: text) != nil else { continue }
            return Match(range: range, template: rule.replacement, suffix: suffix)
        }
        return nil
    }
    static func render(_ template: String, date: Date, locale: Locale, timeZone: TimeZone, clipboard: () -> String?) -> String? {
        guard template.utf16.count <= 16_384 else { return nil }
        let pattern = #"\{\{(date(?::[^{}]{1,100})?|time|clipboard)\}\}"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: template.utf16.count))
        var result = template
        var clipboardValue: String?
        var readClipboard = false
        for match in matches.reversed() {
            guard let tokenRange = Range(match.range(at: 1), in: template), let replacementRange = Range(match.range, in: result) else { return nil }
            let token = String(template[tokenRange])
            let value: String
            if token == "clipboard" {
                if !readClipboard { clipboardValue = clipboard(); readClipboard = true }
                guard let clipboardValue, clipboardValue.utf16.count <= 16_384 else { return nil }
                value = clipboardValue
            } else {
                let formatter = DateFormatter()
                formatter.locale = locale; formatter.timeZone = timeZone
                if token == "time" { formatter.timeStyle = .short }
                else if token == "date" { formatter.dateStyle = .medium }
                else { formatter.dateFormat = String(token.dropFirst(5)) }
                value = formatter.string(from: date)
            }
            result.replaceSubrange(replacementRange, with: value)
            guard result.utf16.count <= 16_384 else { return nil }
        }
        return result
    }
}

enum SnippetEditTransaction {
    struct Snapshot: Equatable { var text: String; var selection: NSRange }
    static func apply(original: Snapshot, match: SnippetExpansionPolicy.Match, replacement: String,
                      read: () -> Snapshot?, stillCurrent: () -> Bool,
                      select: (NSRange) -> Bool, replace: (String) -> Bool) -> Bool {
        guard replacement.utf16.count <= 16_384, Range(match.range, in: original.text) != nil,
              original.selection.length == 0, stillCurrent(), read() == original else { return false }
        guard select(match.range) else { return false }
        let selected = Snapshot(text: original.text, selection: match.range)
        func restoreIfUnchanged() {
            if stillCurrent(), read() == selected { _ = select(original.selection) }
        }
        guard stillCurrent(), read() == selected else { restoreIfUnchanged(); return false }
        let success = replace(replacement)
        if !success { restoreIfUnchanged() }
        return success
    }
}
#endif
