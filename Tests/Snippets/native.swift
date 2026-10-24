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
guard let original = read(), let match = SnippetExpansionPolicy.match(text: original.text, selection: original.selection,
    rules: [.init(trigger: ";hello", replacement: "Hello fixture")], afterDelimiter: true) else { finish(1, "FAIL: native fixture initial value/caret did not match") }
let success = SnippetEditTransaction.apply(original: original, match: match, replacement: "Hello fixture ", read: read,
    stillCurrent: { fixture?.isTerminated == false }, select: { range in
        var raw = CFRange(location: range.location, length: range.length)
        guard let wrapped = AXValueCreate(.cfRange, &raw) else { return false }
        return AXUIElementSetAttributeValue(text, kAXSelectedTextRangeAttribute as CFString, wrapped) == .success
    }, replace: { AXUIElementSetAttributeValue(text, kAXSelectedTextAttribute as CFString, $0 as CFString) == .success })
require(success, "native selected-text transaction was refused")
require(read()?.text == "Hello fixture ", "native fixture text did not update")
finish(0, "Passed background fixture AX range/selected-text replacement and native secure-field subrole checks; no user app, clipboard or keyboard input was accessed. Foreground routing and secure-field enforcement remain untested.")
