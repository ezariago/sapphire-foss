#if !SAPPHIRE_FULL_BUILD
import Foundation
import AppKit

struct PhoneCopiedLinkPrompt: Equatable, Identifiable {
    let id: UUID
    let url: URL
    let expiresAt: TimeInterval
}
enum PhoneCopiedLinkPolicy {
    static func extract(_ text: String) -> URL? {
        guard text.utf8.count < 12000,
              let pattern = try? NSRegularExpression(pattern: "https?://[^\\s<>\"']+", options: .caseInsensitive) else { return nil }
        let ns = text as NSString
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var candidate = ns.substring(with: match.range)
            while let last = candidate.last {
                let punctuation = ".,!?;:".contains(last)
                let closing: [Character: Character] = [")": "(", "]": "[", "}": "{"]
                let unbalanced = closing[last].map { opening in candidate.filter { $0 == last }.count > candidate.filter { $0 == opening }.count } ?? false
                guard punctuation || unbalanced else { break }
                candidate.removeLast()
            }
            if let url = PhoneHandoffURL.parse(candidate) { return url }
        }
        return nil
    }
    static func offer(_ text: String, now: TimeInterval) -> PhoneCopiedLinkPrompt? {
        guard now.isFinite, let url = extract(text) else { return nil }
        return PhoneCopiedLinkPrompt(id: UUID(), url: url, expiresAt: now + 5)
    }
    static func valid(_ prompt: PhoneCopiedLinkPrompt, now: TimeInterval) -> Bool {
        now.isFinite && now < prompt.expiresAt && now >= prompt.expiresAt - 5
    }
}
enum PhoneClipboardDelivery {
    static let marker = NSPasteboard.PasteboardType("com.sapphire.continuity.remote")
    @discardableResult static func write(_ text: String, to board: NSPasteboard) -> Bool {
        guard !text.isEmpty, text.utf8.count < 12000, !text.contains("\0") else { return false }
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string), item.setString("phone", forType: marker) else { return false }
        board.clearContents()
        return board.writeObjects([item])
    }
}
#endif
