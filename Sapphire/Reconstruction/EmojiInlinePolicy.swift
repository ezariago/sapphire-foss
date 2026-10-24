#if !SAPPHIRE_FULL_BUILD
import Foundation
import CoreGraphics

struct EmojiInlineChoice: Equatable, Identifiable {
    let id: String
    let emoji: String
}
enum EmojiInlinePolicy {
    struct Token: Equatable { let range: NSRange; let choices: [EmojiInlineChoice] }
    static let catalog: [EmojiInlineChoice] = [
        .init(id: "smile", emoji: "😄"), .init(id: "smiley", emoji: "😃"), .init(id: "laughing", emoji: "😆"),
        .init(id: "joy", emoji: "😂"), .init(id: "wink", emoji: "😉"), .init(id: "heart", emoji: "❤️"),
        .init(id: "heart_eyes", emoji: "😍"), .init(id: "thumbsup", emoji: "👍"), .init(id: "+1", emoji: "👍"),
        .init(id: "thumbsdown", emoji: "👎"), .init(id: "wave", emoji: "👋"), .init(id: "clap", emoji: "👏"),
        .init(id: "pray", emoji: "🙏"), .init(id: "rocket", emoji: "🚀"), .init(id: "tada", emoji: "🎉"),
        .init(id: "fire", emoji: "🔥"), .init(id: "sparkles", emoji: "✨"), .init(id: "star", emoji: "⭐️"),
        .init(id: "check", emoji: "✅"), .init(id: "warning", emoji: "⚠️"), .init(id: "eyes", emoji: "👀"),
        .init(id: "thinking", emoji: "🤔"), .init(id: "cry", emoji: "😢"), .init(id: "coffee", emoji: "☕️")
    ]
    static func match(text: String, selection: NSRange) -> Token? {
        guard text.utf16.count <= 65, selection.length == 0, selection.location >= 0,
              let selected = Range(selection, in: text) else { return nil }
        if let next = text[selected.lowerBound...].first, next.isLetter || next.isNumber || "_+-:".contains(next) { return nil }
        let prefix = String(text[..<selected.lowerBound])
        let closed = prefix.hasSuffix(":")
        let body = closed ? prefix.dropLast() : prefix[...]
        guard let colon = body.lastIndex(of: ":") else { return nil }
        if colon != body.startIndex {
            let before = body[body.index(before: colon)]
            guard before.isWhitespace || "([{\"'".contains(before) else { return nil }
        }
        let query = String(body[body.index(after: colon)...]).lowercased()
        guard (1...30).contains(query.utf8.count), query.unicodeScalars.allSatisfy({ (97...122).contains($0.value) || (48...57).contains($0.value) || "_+-".unicodeScalars.contains($0) }) else { return nil }
        let choices = Array(catalog.filter { closed ? $0.id == query : $0.id.hasPrefix(query) }.prefix(5))
        guard !choices.isEmpty else { return nil }
        let length = prefix[colon...].utf16.count
        return Token(range: NSRange(location: selection.location - length, length: length), choices: choices)
    }
    static func panelFrame(caret: CGRect, primaryTop: CGFloat, screens: [CGRect], height: CGFloat) -> CGRect? {
        guard [caret.minX, caret.minY, caret.width, caret.height, primaryTop, height].allSatisfy(\.isFinite),
              caret.width >= 0, caret.height > 0, caret.width < 2048, caret.height < 2048, height > 0 else { return nil }
        let point = CGPoint(x: caret.midX, y: primaryTop - caret.midY)
        guard let screen = screens.first(where: { $0.contains(point) }), screen.width >= 336, screen.height >= height + 16 else { return nil }
        let bottom = primaryTop - caret.maxY
        let proposed = bottom - height - 6 >= screen.minY + 8 ? bottom - height - 6 : primaryTop - caret.minY + 6
        return CGRect(x: min(max(caret.minX, screen.minX + 8), screen.maxX - 328),
                      y: min(max(proposed, screen.minY + 8), screen.maxY - height - 8), width: 320, height: height)
    }
}
#endif
