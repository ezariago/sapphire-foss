import Foundation

nonisolated enum PlainTextSanitizer {
    static func sanitize(_ text: String, stripLinks: Bool, stripEmojis: Bool, stripListMarkers: Bool) -> String {
        var result = text
        if stripLinks { result = Self.stripLinks(from: result) }
        if stripEmojis { result = Self.stripEmojis(from: result) }
        if stripListMarkers { result = Self.stripListMarkers(from: result) }
        return result
    }

    private static func stripLinks(from text: String) -> String {
        let pattern = #"(?i)\b(?:https?|ftp)://[^\s<>"']+|www\.[^\s<>"']+|mailto:[^\s<>"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let fullRange = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: fullRange).reversed()
        for match in matches {
            guard let range = Range(match.range, in: result) else { continue }
            var link = result[range]
            while let last = link.last, ".,;:!?)]}»”’\"".contains(last) {
                link = link.dropLast()
            }
            guard !link.isEmpty else { continue }
            let linkRange = link.startIndex..<link.endIndex
            result.replaceSubrange(linkRange, with: "")
        }
        return result
    }

    private static func stripEmojis(from text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let shouldRemove = scalar.properties.isEmojiPresentation
                || (0xFE00...0xFE0F).contains(scalar.value)
                || scalar.value == 0x200D
                || (0x1F3FB...0x1F3FF).contains(scalar.value)
                || (0x1F1E6...0x1F1FF).contains(scalar.value)
                || (0xE0020...0xE007F).contains(scalar.value)
                || scalar.value == 0x20E3
            if !shouldRemove {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func stripListMarkers(from text: String) -> String {
        let pattern = #"(?m)^[ \t]*(?:[•◦‣▪▫⁃·–—]|\*|\+|-|\d+[.)]|\(\d+\))(?=[ \t]|$)[ \t]*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}