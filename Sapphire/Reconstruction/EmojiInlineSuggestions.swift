#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

private final class EmojiInlineInput: @unchecked Sendable {
    let lock = NSLock()
    var gate = SnippetInputGate()
    var panelBounds: CGRect?
    func invalidate() { lock.withLock { gate.invalidate() } }
    func current(_ ticket: SnippetInputGate.Ticket) -> Bool { lock.withLock { gate.isCurrent(ticket) } }
}
private final class EmojiInlinePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class EmojiInlineHosting: NSHostingView<EmojiInlineChoicesView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
struct EmojiInlineChoicesView: View {
    let choices: [EmojiInlineChoice]
    let choose: (EmojiInlineChoice) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Emoji · click to insert").font(.caption).foregroundStyle(.secondary)
            ForEach(choices) { choice in
                Button { choose(choice) } label: {
                    HStack { Text(choice.emoji).font(.title3); Text(":" + choice.id + ":").font(.callout); Spacer() }
                        .contentShape(Rectangle()).padding(.vertical, 3)
                }.buttonStyle(.plain).accessibilityLabel("Insert " + choice.id)
            }
        }.padding(10).frame(width: 320).background(.regularMaterial)
    }
}
@MainActor final class EmojiInlineSuggestionsManager: ObservableObject {
    static let shared = EmojiInlineSuggestionsManager()
    @Published private(set) var status = "Inline suggestions are off."
    private struct Configuration: Equatable {
        let enabled: Bool
        let excluded: Set<String>
        init(_ settings: Settings) { enabled = settings.emojiInlineSuggestionsEnabled; excluded = settings.emojiDisabledAppBundleIDs }
    }
    private struct Offer {
        let id = UUID()
        let target: AXUIElement
        let capture: EmojiInlineAX.Capture
        let ticket: SnippetInputGate.Ticket
        let appID: String
        let launched: Date
        let created: TimeInterval
        let configuration: Configuration
    }
    private let input = EmojiInlineInput()
    private var subscription: AnyCancellable?
    private var tap: GlobalEventTap.Token?
    private var observers: [NSObjectProtocol] = [], lockObservers: [NSObjectProtocol] = []
    private var panel: EmojiInlinePanel?
    private var offer: Offer?
    private var expiry: Task<Void, Never>?
    private init() {}
    func start() {
        guard subscription == nil else { return }
        subscription = SettingsModel.shared.$settings.map(Configuration.init).removeDuplicates().sink { [weak self] configuration in
            self?.configure(configuration)
        }
        let center = NSWorkspace.shared.notificationCenter
        observers = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidResignActiveNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.reset() } }
        }
        lockObservers = ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"].map { name in
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.reset() } }
        }
    }
    private func configure(_ config: Configuration) {
        reset()
        input.lock.withLock { input.gate.configure(enabled: config.enabled) }
        status = config.enabled ? "Type a colon alias, then click a suggestion. Requires Accessibility and a supported text editor." : "Inline suggestions are off."
        if !config.enabled { if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil; return }
        guard tap == nil else { return }
        let input = input
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        tap = GlobalEventTap.shared.register(name: "FOSSEmojiInline", mask: types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }, priority: EventTapPriority.observer, reset: { [weak self] in
            input.invalidate(); DispatchQueue.main.async { self?.hide() }
        }) { [weak self] type, event in
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type), input.lock.withLock({ input.panelBounds?.contains(event.location) == true }) { return .pass }
            let ticket: SnippetInputGate.Ticket? = input.lock.withLock {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let printable = ((0...51).contains(code) && code != 36 && code != 48) || [65,67,69,75,78,81,117].contains(code) || (82...95).contains(code)
                let eligible = printable && event.flags.intersection([.maskCommand,.maskControl,.maskAlternate,.maskSecondaryFn]).isEmpty
                    && event.getIntegerValueField(.eventSourceUserData) == 0 && event.getIntegerValueField(.keyboardEventAutorepeat) == 0
                let target = event.getIntegerValueField(.eventTargetUnixProcessID)
                if type == .keyDown { input.gate.down(code, eligible: eligible, target: target); return nil }
                if type == .keyUp { return input.gate.up(code, eligible: eligible, target: target) }
                input.gate.invalidate(); return nil
            }
            DispatchQueue.main.async {
                self?.hide()
                if let ticket { self?.inspect(ticket) }
            }
            return .pass
        }
    }
    private func reset() {
        input.lock.withLock { input.gate.foreground(NSWorkspace.shared.frontmostApplication?.processIdentifier) }
        hide()
    }
    private static func unlocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any], session[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
        return !(session["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }
    private static func layoutInput() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(), let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        return CFEqual(Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue(), kTISTypeKeyboardLayout)
    }
    private func ready(_ ticket: SnippetInputGate.Ticket, config: Configuration) -> NSRunningApplication? {
        guard config.enabled, Configuration(SettingsModel.shared.current) == config, input.current(ticket),
              AXIsProcessTrusted(), !IsSecureEventInputEnabled(), Self.unlocked(), Self.layoutInput(),
              !AppLockManager.shared.isLocked, NSEvent.pressedMouseButtons == 0,
              NSEvent.modifierFlags.intersection([.command,.control,.option]).isEmpty,
              !NSApp.windows.contains(where: { $0.isVisible && $0.level.rawValue >= NSWindow.Level.screenSaver.rawValue }),
              let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular, app.processIdentifier == ticket.pid,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = app.bundleIdentifier, !config.excluded.contains(id) else { return nil }
        return app
    }
    private func inspect(_ ticket: SnippetInputGate.Ticket) {
        let config = Configuration(SettingsModel.shared.current)
        guard let app = ready(ticket, config: config), let launched = app.launchDate, let id = app.bundleIdentifier else { return }
        let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system,0.04)
        guard let target: AXUIElement = EmojiInlineAX.attribute(system,kAXFocusedUIElementAttribute) else { return }
        AXUIElementSetMessagingTimeout(target,0.04)
        var pid: pid_t = 0
        guard AXUIElementGetPid(target,&pid) == .success, pid == ticket.pid,
              let capture = EmojiInlineAX.capture(target), ready(ticket,config:config) != nil else { return }
        let caret = NSRange(location: capture.window.location + capture.original.selection.location,length:0)
        let word = NSRange(location:capture.window.location + capture.token.range.location,length:capture.token.range.length)
        guard let bounds = EmojiInlineAX.bounds(target,caret) ?? EmojiInlineAX.bounds(target,word),
              let primary = NSScreen.screens.first(where: { $0.frame.origin == .zero }),
              let frame = EmojiInlinePolicy.panelFrame(caret:bounds,primaryTop:primary.frame.maxY,screens:NSScreen.screens.map(\.visibleFrame),height:CGFloat(capture.token.choices.count * 36 + 42)) else { return }
        let value = Offer(target:target,capture:capture,ticket:ticket,appID:id,launched:launched,created:ProcessInfo.processInfo.systemUptime,configuration:config)
        offer = value
        let panel = EmojiInlinePanel(contentRect:frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.isFloatingPanel = true
        panel.level = .popUpMenu; panel.sharingType = .none; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        panel.contentView = EmojiInlineHosting(rootView:EmojiInlineChoicesView(choices:capture.token.choices,choose:{ [weak self] choice in self?.choose(choice,id:value.id) }))
        self.panel = panel
        input.lock.withLock { input.panelBounds = CGRect(x:frame.minX,y:primary.frame.maxY-frame.maxY,width:frame.width,height:frame.height) }
        panel.orderFrontRegardless()
        expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for:.seconds(5))
            guard !Task.isCancelled, self?.offer?.id == value.id else { return }; self?.hide()
        }
    }
    private func choose(_ choice: EmojiInlineChoice, id: UUID) {
        guard let value = offer, value.id == id else { return }
        func current() -> Bool {
            let now = ProcessInfo.processInfo.systemUptime
            guard now >= value.created, now-value.created < 5, let app = ready(value.ticket,config:value.configuration),
                  app.bundleIdentifier == value.appID, app.launchDate == value.launched else { return false }
            let system = AXUIElementCreateSystemWide(); AXUIElementSetMessagingTimeout(system,0.04)
            guard let focused: AXUIElement = EmojiInlineAX.attribute(system,kAXFocusedUIElementAttribute) else { return false }
            return CFEqual(focused,value.target)
        }
        let success = current() && EmojiInlineAX.apply(value.target,capture:value.capture,choice:choice,stillCurrent:current)
        hide(); status = success ? "Inserted :\(choice.id):." : "The editor changed or did not confirm insertion."
    }
    private func hide() {
        expiry?.cancel(); expiry = nil; offer = nil
        input.lock.withLock { input.panelBounds = nil }
        panel?.orderOut(nil); panel?.close(); panel = nil
    }
    func stop() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        subscription = nil; observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
        lockObservers.forEach(DistributedNotificationCenter.default().removeObserver); lockObservers.removeAll()
        input.lock.withLock { input.gate.configure(enabled:false) }; hide()
    }
}
#endif
