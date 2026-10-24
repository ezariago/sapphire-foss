import AppKit
import ApplicationServices

guard AXIsProcessTrusted() else { print("SKIP: AX fixture permission unavailable; no prompt requested."); exit(77) }
let application = NSApplication.shared
application.setActivationPolicy(.accessory)
var fixture: NSRunningApplication?
func finish(_ status: Int32, _ message: String) -> Never {
    fixture?.terminate()
    let end = Date().addingTimeInterval(2)
    while let fixture, !fixture.isTerminated, Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    if fixture?.isTerminated == false { print("FAIL: fixture did not terminate within cleanup deadline"); exit(1) }
    print(message)
    exit(status)
}
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { finish(1, "FAIL: \(message)") }
}
let config = NSWorkspace.OpenConfiguration()
config.activates = false
let prefix = CommandLine.arguments.contains("--long-prefix") ? String(repeating:"😀",count:40) + " " : "Hello "
if CommandLine.arguments.contains("--long-prefix") { config.arguments = ["--long-prefix"] }
config.createsNewApplicationInstance = true
NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: CommandLine.arguments[1]), configuration: config) { app, error in
    DispatchQueue.main.async {
        guard let app, error == nil else { finish(1, "FAIL: could not launch isolated snippet fixture") }
        fixture = app
    }
}
let deadline = Date().addingTimeInterval(15)
func attr(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}
func find(_ element: AXUIElement, subrole: String? = nil, role: String? = nil, depth: Int = 0) -> AXUIElement? {
    guard depth < 12 else { return nil }
    AXUIElementSetMessagingTimeout(element, 0.2)
    if let role, attr(element, kAXRoleAttribute) as? String == role { return element }
    if let subrole, attr(element, kAXSubroleAttribute) as? String == subrole { return element }
    for child in (attr(element, kAXChildrenAttribute) as? [AXUIElement] ?? []) {
        if let match = find(child, subrole: subrole, role: role, depth: depth + 1) { return match }
    }
    return nil
}
var text: AXUIElement?
var secure: AXUIElement?
while Date() < deadline && (text == nil || secure == nil) {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    guard let fixture else { continue }
    let root = AXUIElementCreateApplication(fixture.processIdentifier)
    AXUIElementSetMessagingTimeout(root, 0.2)
    for window in (attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? []) {
        text = text ?? find(window, role: kAXTextAreaRole)
        secure = secure ?? find(window, subrole: kAXSecureTextFieldSubrole)
    }
}
guard let text, let secure else { finish(1, "FAIL: fixture AX text/secure elements unavailable in this session") }
require(attr(secure, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole, "secure fixture subrole")
for name in [kAXSelectedTextAttribute, kAXSelectedTextRangeAttribute] {
    var writable: DarwinBoolean = false
    require(AXUIElementIsAttributeSettable(text, name as CFString, &writable) == .success && writable.boolValue, "native text attribute not writable: \(name)")
}
func read() -> SnippetEditTransaction.Snapshot? {
    guard let value = attr(text, kAXValueAttribute) as? String,
          let raw = attr(text, kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    let wrapped = unsafeBitCast(raw, to: AXValue.self)
    var range = CFRange()
    guard AXValueGetType(wrapped) == .cfRange, AXValueGetValue(wrapped, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
    return .init(text: value, selection: NSRange(location: range.location, length: range.length))
}
guard EmojiInlineAX.capture(secure) == nil else { finish(1, "FAIL: synthetic secure field accepted") }
guard let capture = EmojiInlineAX.capture(text), let choice = capture.token.choices.first(where: { $0.id == "smile" }) else {
    finish(1,"FAIL: native bounded text-range capture/alias was unavailable")
}
require(capture.window.length <= 65, "bounded native read window")
let success = EmojiInlineAX.apply(text,capture:capture,choice:choice,stillCurrent:{fixture?.isTerminated == false})
require(success,"native emoji replacement was refused or unconfirmed")
require(read()?.text == prefix + "😄", "native emoji text did not update")
require(read()?.selection == NSRange(location:prefix.utf16.count+2,length:0), "native caret did not collapse after inserted emoji")
finish(0,"Passed bounded native parameterized text-range/emoji replacement, caret and secure-field refusal on the owned background fixture. No user document, clipboard, key posting or foreground app change. Global routing and actual popup clicking remain unverified.")
