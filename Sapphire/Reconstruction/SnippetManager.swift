#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

private final class SnippetInputState: @unchecked Sendable {
    let lock = NSLock()
    var gate = SnippetInputGate()
    func invalidate() { lock.withLock { gate.invalidate() } }
    func isCurrent(_ ticket: SnippetInputGate.Ticket) -> Bool { lock.withLock { gate.isCurrent(ticket) } }
}

@MainActor
final class SnippetManager {
    static let shared = SnippetManager()
    private let input = SnippetInputState()
    private var tap: GlobalEventTap.Token?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private struct Configuration: Equatable {
        var enabled: Bool
        var afterDelimiter: Bool
        var rules: [SnippetExpansionPolicy.Rule]
        init(_ settings: Settings) {
            enabled = settings.snippetsEnabled
            afterDelimiter = settings.snippetsExpandAfterSpace
            rules = settings.snippetsList.map { .init(trigger: $0.trigger, replacement: $0.replacement, enabled: $0.isEnabled) }
        }
    }
    private init() {}
    func start() {
        guard subscription == nil else { return }
        let input = input
        input.lock.withLock { input.gate.foreground(NSWorkspace.shared.frontmostApplication?.processIdentifier) }
        subscription = SettingsModel.shared.$settings.sink { settings in
            input.lock.withLock { input.gate.configure(enabled: settings.snippetsEnabled) }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    let pid = name == NSWorkspace.willSleepNotification ? nil : NSWorkspace.shared.frontmostApplication?.processIdentifier
                    input.lock.withLock { input.gate.foreground(pid) }
                }
            })
        }
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = GlobalEventTap.shared.register(name: "FOSSSnippets", mask: mask, priority: EventTapPriority.observer,
            reset: { input.invalidate() }) { [weak self] type, event in
                let ticket: SnippetInputGate.Ticket? = input.lock.withLock {
                    let code = event.getIntegerValueField(.keyboardEventKeycode)
                    // Return/Tab can change focus or submit a field; they never trigger expansion.
                    let printable = ((0...50).contains(code) && code != 36 && code != 48) || [65, 67, 69, 75, 78, 81].contains(code) || (82...95).contains(code)
                    let eligible = printable && event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
                        && event.getIntegerValueField(.keyboardEventAutorepeat) == 0
                    let target = event.getIntegerValueField(.eventTargetUnixProcessID)
                    if type == .keyDown { input.gate.down(code, eligible: eligible, target: target); return nil }
                    if type == .keyUp { return input.gate.up(code, eligible: eligible, target: target) }
                    input.gate.invalidate(); return nil
                }
                if let ticket {
                    DispatchQueue.main.async { [weak self] in self?.expand(ticket: ticket) }
                }
                return .pass
            }
    }
    private func expand(ticket: SnippetInputGate.Ticket) {
        guard input.isCurrent(ticket), AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              NSEvent.pressedMouseButtons == 0,
              NSEvent.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular,
              front.processIdentifier == ticket.pid,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let config = Configuration(SettingsModel.shared.current)
        guard config.enabled, !config.rules.isEmpty, config.rules.count <= 1000 else { return }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        guard let target: AXUIElement = SystemEnhanceWindowRegistry.attribute(system, kAXFocusedUIElementAttribute) else { return }
        AXUIElementSetMessagingTimeout(target, 0.05)
        var pid: pid_t = 0
        guard AXUIElementGetPid(target, &pid) == .success, pid == front.processIdentifier,
              let role: String = SystemEnhanceWindowRegistry.attribute(target, kAXRoleAttribute),
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) else { return }
        let subrole: String = SystemEnhanceWindowRegistry.attribute(target, kAXSubroleAttribute) ?? ""
        guard subrole != kAXSecureTextFieldSubrole,
              (SystemEnhanceWindowRegistry.attribute(target, "AXProtectedContent") as Bool?) != true else { return }
        for attribute in [kAXSelectedTextRangeAttribute, kAXSelectedTextAttribute] {
            var settable: DarwinBoolean = false
            guard AXUIElementIsAttributeSettable(target, attribute as CFString, &settable) == .success, settable.boolValue else { return }
        }
        // Editors exposing marked text are left alone while composing an input-method sequence.
        func rangeAttribute(_ name: String) -> CFRange? {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(target, name as CFString, &raw) == .success,
                  let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            let value = unsafeBitCast(raw, to: AXValue.self)
            var range = CFRange()
            guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else { return nil }
            return range
        }
        if let marked = rangeAttribute("AXMarkedTextRange"), marked.length > 0 { return }
        func read() -> SnippetEditTransaction.Snapshot? {
            guard let value: String = SystemEnhanceWindowRegistry.attribute(target, kAXValueAttribute), value.utf16.count <= 1_000_000,
                  let range = rangeAttribute(kAXSelectedTextRangeAttribute), range.location >= 0, range.length >= 0 else { return nil }
            return .init(text: value, selection: NSRange(location: range.location, length: range.length))
        }
        guard let original = read(), let match = SnippetExpansionPolicy.match(text: original.text, selection: original.selection,
            rules: config.rules, afterDelimiter: config.afterDelimiter) else { return }
        func stillCurrent() -> Bool {
            guard input.isCurrent(ticket), AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
                  NSEvent.pressedMouseButtons == 0,
                  NSEvent.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  Configuration(SettingsModel.shared.current) == config,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let focused: AXUIElement = SystemEnhanceWindowRegistry.attribute(system, kAXFocusedUIElementAttribute) else { return false }
            let currentSubrole: String = SystemEnhanceWindowRegistry.attribute(target, kAXSubroleAttribute) ?? ""
            return CFEqual(focused, target) && currentSubrole != kAXSecureTextFieldSubrole
                && (SystemEnhanceWindowRegistry.attribute(target, "AXProtectedContent") as Bool?) != true
                && (rangeAttribute("AXMarkedTextRange")?.length ?? 0) <= 0
        }
        guard stillCurrent(), let replacement = SnippetExpansionPolicy.render(match.template, date: Date(), locale: .current, timeZone: .current,
            clipboard: { NSPasteboard.general.string(forType: .string) }) else { return }
        _ = SnippetEditTransaction.apply(original: original, match: match, replacement: replacement + match.suffix,
            read: read, stillCurrent: stillCurrent, select: { range in
                var raw = CFRange(location: range.location, length: range.length)
                guard let value = AXValueCreate(.cfRange, &raw) else { return false }
                return AXUIElementSetAttributeValue(target, kAXSelectedTextRangeAttribute as CFString, value) == .success
            }, replace: { AXUIElementSetAttributeValue(target, kAXSelectedTextAttribute as CFString, $0 as CFString) == .success })
    }
    func removeHandler() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        subscription = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
        input.lock.withLock { input.gate.configure(enabled: false) }
    }
}
#endif
