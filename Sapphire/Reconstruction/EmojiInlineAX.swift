#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices

enum EmojiInlineAX {
    struct Capture {
        let window: NSRange
        let original: SnippetEditTransaction.Snapshot
        let token: EmojiInlinePolicy.Token
    }
    static func attribute<T>(_ target: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
    static func range(_ target: AXUIElement, _ name: String = kAXSelectedTextRangeAttribute) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(target, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let wrapped = unsafeBitCast(value, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetType(wrapped) == .cfRange, AXValueGetValue(wrapped, .cfRange, &range),
              range.location >= 0, range.length >= 0, range.location <= 1_000_000, range.length <= 1_000_000 - range.location else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
    private static func wrapped(_ range: NSRange) -> AXValue? {
        var raw = CFRange(location: range.location, length: range.length)
        return AXValueCreate(.cfRange, &raw)
    }
    static func text(_ target: AXUIElement, _ range: NSRange) -> String? {
        guard range.length <= 65, let raw = wrapped(range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(target, kAXStringForRangeParameterizedAttribute as CFString, raw, &value) == .success,
              let string = value as? String, string.utf16.count == range.length else { return nil }
        return string
    }
    static func eligible(_ target: AXUIElement) -> Bool {
        guard let role: String = attribute(target, kAXRoleAttribute), [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              (attribute(target, kAXSubroleAttribute) as String?) != kAXSecureTextFieldSubrole,
              (attribute(target, "AXProtectedContent") as Bool?) != true,
              (range(target, "AXMarkedTextRange")?.length ?? 0) == 0 else { return false }
        for name in [kAXSelectedTextRangeAttribute, kAXSelectedTextAttribute] {
            var writable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(target, name as CFString, &writable) == .success, writable.boolValue else { return false }
        }
        return true
    }
    static func capture(_ target: AXUIElement) -> Capture? {
        guard eligible(target), let caret = range(target), caret.length == 0,
              let count: Int = attribute(target, kAXNumberOfCharactersAttribute), count >= caret.location, count <= 1_000_000 else { return nil }
        let start = max(0, caret.location - 64), end = min(count, caret.location + 1)
        let window = NSRange(location: start, length: end - start)
        guard let value = text(target, window) else { return nil }
        let selection = NSRange(location: caret.location - start, length: 0)
        guard let token = EmojiInlinePolicy.match(text: value, selection: selection) else { return nil }
        return Capture(window: window, original: .init(text: value, selection: selection), token: token)
    }
    static func bounds(_ target: AXUIElement, _ range: NSRange) -> CGRect? {
        guard let raw = wrapped(range) else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(target, kAXBoundsForRangeParameterizedAttribute as CFString, raw, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let wrapped = unsafeBitCast(value, to: AXValue.self); var bounds = CGRect.zero
        guard AXValueGetType(wrapped) == .cgRect, AXValueGetValue(wrapped, .cgRect, &bounds) else { return nil }
        return bounds
    }
    static func apply(_ target: AXUIElement, capture: Capture, choice: EmojiInlineChoice, stillCurrent: () -> Bool) -> Bool {
        guard capture.token.choices.contains(choice) else { return false }
        func read() -> SnippetEditTransaction.Snapshot? {
            guard let string = text(target, capture.window), let selected = range(target), selected.location >= capture.window.location else { return nil }
            return .init(text: string, selection: NSRange(location: selected.location - capture.window.location, length: selected.length))
        }
        let result = SnippetEditTransaction.apply(original: capture.original,
            match: .init(range: capture.token.range, template: choice.emoji, suffix: ""), replacement: choice.emoji,
            read: read, stillCurrent: { stillCurrent() && eligible(target) }, select: { range in
                guard let raw = wrapped(NSRange(location: capture.window.location + range.location, length: range.length)) else { return false }
                return AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, raw) == .success
            }, replace: { AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, $0 as CFString) == .success })
        guard result else { return false }
        let inserted = NSRange(location: capture.window.location + capture.token.range.location, length: choice.emoji.utf16.count)
        guard stillCurrent(), text(target, inserted) == choice.emoji else { return false }
        if range(target) == inserted, let caret = wrapped(NSRange(location: NSMaxRange(inserted), length: 0)), stillCurrent() {
            _ = AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, caret)
        }
        return true
    }
}
#endif
