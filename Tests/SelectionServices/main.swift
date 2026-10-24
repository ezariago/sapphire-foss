import AppKit
@main struct Checks {
    @MainActor static func main() throws {
        var config = SelectionServiceConfiguration()
        let provider = SystemEnhanceContextMenu(configuration: { config })
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        func put(_ text: String) { board.clearContents(); assert(board.setString(text, forType: .string)) }
        func call(_ action: SelectionServiceAction, succeeds: Bool = true) {
            var error: NSString?
            if action == .cleanText { provider.cleanSelectedText(board, userData: nil, error: &error) }
            else { provider.cleanSelectedURL(board, userData: nil, error: &error) }
            assert((error == nil) == succeeds, error.map(String.init) ?? "missing expected error")
        }
        put("Fixture"); let disabledRevision = board.changeCount
        call(.cleanText, succeeds: false); assert(board.changeCount == disabledRevision)
        config.enabled = true
        config.stripLinks = true; config.stripEmojis = true; config.stripListMarkers = true
        put("• Hello 😀 https://example.invalid/path.\n2. Keep this")
        call(.cleanText); assert(board.string(forType: .string) == "Hello  .\nKeep this")
        assert(board.pasteboardItems?.count == 1 && board.types?.contains(.rtf) != true)
        config.customTrackingParameters = ["custom"]
        put("https://example.invalid/a?utm_source=fixture&keep=a%2Bb&custom=remove#fragment")
        call(.cleanURL); assert(board.string(forType: .string) == "https://example.invalid/a?keep=a%2Bb#fragment")
        let signed = "https://example.invalid/a?sig=abc&utm_source=keep"
        put(signed); call(.cleanURL); assert(board.string(forType: .string) == signed)
        for input in ["file:///tmp/fixture", "javascript:alert(1)", "https://example.invalid/ a", "two URLs https://example.invalid", "\u{0}", String(repeating: "a", count: 65537)] {
            put(input); let revision = board.changeCount
            call(.cleanURL, succeeds: false); assert(board.changeCount == revision && board.string(forType: .string) == input)
        }
        config.stripLinks = false; config.stripEmojis = false; config.stripListMarkers = false
        let exact = String(repeating: "a", count: 65536)
        put(exact); call(.cleanText); assert(board.string(forType: .string) == exact)
        put("🧑🏽‍💻 Family 👨‍👩‍👧‍👦 · Καλημέρα · 123")
        call(.cleanText); assert(board.string(forType: .string) == "🧑🏽‍💻 Family 👨‍👩‍👧‍👦 · Καλημέρα · 123")
        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
            let item = NSPasteboardItem(); item.setString("Secret fixture", forType: .string); item.setData(Data(), forType: .init(marker))
            board.clearContents(); board.writeObjects([item]); let revision = board.changeCount
            call(.cleanText, succeeds: false); assert(board.changeCount == revision)
        }
        let first = NSPasteboardItem(), second = NSPasteboardItem()
        first.setString("a", forType: .string); second.setString("b", forType: .string)
        board.clearContents(); board.writeObjects([first, second]); let multiRevision = board.changeCount
        call(.cleanText, succeeds: false); assert(board.changeCount == multiRevision)
        board.clearContents(); board.setData(Data([0xff, 0xfe, 0xff]), forType: .string)
        let invalidRevision = board.changeCount; call(.cleanText, succeeds: false); assert(board.changeCount == invalidRevision)
        put("Fixture")
        var reads = 0
        let reconfigured = SystemEnhanceContextMenu(configuration: {
            reads += 1
            return SelectionServiceConfiguration(enabled: reads == 1)
        })
        var error: NSString?
        let reconfiguredRevision = board.changeCount
        reconfigured.cleanSelectedText(board, userData: nil, error: &error)
        assert(error != nil && board.changeCount == reconfiguredRevision)
        reads = 0
        let changedBoard = SystemEnhanceContextMenu(configuration: {
            reads += 1
            if reads == 2 { board.clearContents(); board.setString("Newer selection", forType: .string) }
            return SelectionServiceConfiguration(enabled: true)
        })
        changedBoard.cleanSelectedText(board, userData: nil, error: &error)
        assert(error != nil && board.string(forType: .string) == "Newer selection")
        var excessive = SelectionServiceConfiguration(enabled: true)
        excessive.customTrackingParameters = Array(repeating: "a", count: 257)
        assert(SelectionServicePolicy.transform("https://example.invalid/?utm_source=fixture", action: .cleanURL, configuration: excessive) == nil)
        // Exercise the real Objective-C entry points named in the shipped plist.
        let services = try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: "scripts/public-services.plist")), format: nil) as! [[String: Any]]
        assert(services.count == 2)
        for service in services {
            let selector = NSSelectorFromString((service["NSMessage"] as! String) + ":userData:error:")
            assert(provider.responds(to: selector))
            assert(service["NSSendTypes"] as? [String] == [NSPasteboard.PasteboardType.string.rawValue])
            assert(service["NSReturnTypes"] as? [String] == [NSPasteboard.PasteboardType.string.rawValue])
        }
        print("Passed real Services selectors, isolated named-pasteboard replacement/refusal, conservative URL preservation, Unicode/exact limits and configured text cleanup. General clipboard, user selections and Services registration were untouched.")
    }
}
