#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

extension MouseRemapConfiguration {
    init(_ settings: Settings) {
        enabled = settings.mouseButtonRemappingEnabled
        actions = [2: settings.mouseMiddleButtonAction.rawValue, 3: settings.mouseButton4Action.rawValue, 4: settings.mouseButton5Action.rawValue]
        modified = [2: settings.mouseMiddleModifiedAction.rawValue, 3: settings.mouseButton4ModifiedAction.rawValue, 4: settings.mouseButton5ModifiedAction.rawValue]
        keyboardModifier = UInt64(settings.mouseModifierSelection.rawValue)
        modifierButtonEnabled = settings.mouseModifierButtonEnabled; modifierButton = settings.mouseModifierButtonNumber
        excluded = Set(settings.mouseExcludedAppBundleIDs)
        protectsClose = settings.systemEnhanceQuitProtectionEnabled && settings.systemEnhanceQuitProtectionProtectClose
        closeExcluded = Set(settings.systemEnhanceQuitProtectionExcludedApps)
    }
}
private final class MouseButtonRemapState: @unchecked Sendable {
    let lock = NSLock()
    var policy = MouseButtonRemapPolicy()
    var deliveryPending = false
}
private struct MouseAXSelection: @unchecked Sendable { let element: AXUIElement }

@MainActor
final class MouseButtonRemapManager: ObservableObject {
    static let shared = MouseButtonRemapManager()
    @Published private(set) var status = "Button remapping is off."
    private let state = MouseButtonRemapState()
    private var subscription: AnyCancellable?
    private var tap: GlobalEventTap.Token?
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var sleeping = false
    private var locked = false
    private static let lookupQueue = DispatchQueue(label: "Sapphire.MouseMenuLookup", qos: .userInitiated)
    private lazy var delivery = MouseMenuDelivery<MouseAXSelection>(clock: { ProcessInfo.processInfo.systemUptime },
        validate: { [weak self] in self?.validate($0) == true }, resolve: { request in
            await withCheckedContinuation { continuation in Self.lookupQueue.async { continuation.resume(returning: Self.resolve(request)) } }
        }, perform: { [weak self] selection, request in
            guard Self.attribute(selection.element, kAXEnabledAttribute) as Bool? == true,
                  self?.validate(request) == true else { return false }
            return AXUIElementPerformAction(selection.element, kAXPressAction as CFString) == .success
        }, report: { [weak self] success in self?.status = success ? "Requested the enabled app menu command." : "No matching enabled menu command was available, or the app declined it." },
        finished: { [weak self] in guard let self else { return }; self.state.lock.withLock { self.state.deliveryPending = false } })
    private init() {}
    func start() {
        guard subscription == nil else { return }; sleeping = false; locked = false; delivery.start()
        updateForeground()
        let state = state
        subscription = SettingsModel.shared.$settings.map(MouseRemapConfiguration.init).removeDuplicates().sink { [weak self] configuration in
            state.lock.withLock { state.policy.configure(configuration) }
            self?.status = configuration.enabled ? "Ready for mapped middle/side clicks. Requires Accessibility." : "Button remapping is off."
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }
                if name == NSWorkspace.willSleepNotification { self.sleeping = true }
                if name == NSWorkspace.didWakeNotification { self.sleeping = false }
                self.state.lock.withLock { self.state.policy.invalidate() }; self.updateForeground()
            } })
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }; self.locked = name == "com.apple.screenIsLocked"
                self.state.lock.withLock { self.state.policy.invalidate() }; self.updateForeground()
            } })
        }
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = GlobalEventTap.shared.register(name: "FOSSMouseButtons", mask: mask, priority: EventTapPriority.filter + 10,
            reset: { state.lock.withLock { state.policy.invalidate(retainConsumed: false) } }) { [weak self] type, event in
                if [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel].contains(type) {
                    state.lock.withLock { if state.policy.configuration.enabled || state.deliveryPending { state.policy.invalidate() } }
                    return .pass
                }
                guard let input = MouseButtonEventAdapter.input(type: type, event: event,
                    secureInput: IsSecureEventInputEnabled(), now: ProcessInfo.processInfo.systemUptime) else {
                    if type == .otherMouseDown { state.lock.withLock { state.policy.invalidate() } }; return .pass
                }
                let result = state.lock.withLock { () -> MouseRemapDecision in
                    let result = state.policy.handle(input)
                    if case .pass = result, type == .otherMouseDown { state.policy.invalidate() }
                    return result
                }
                switch result {
                case .pass: return .pass
                case .swallow: return .swallow
                case .execute(let request):
                    let schedule = state.lock.withLock { () -> Bool in
                        guard !state.deliveryPending else { return false }; state.deliveryPending = true; return true
                    }
                    if schedule {
                        DispatchQueue.main.async { MainActor.assumeIsolated {
                            guard let self, self.delivery.submit(request) else { state.lock.withLock { state.deliveryPending = false }; return }
                        } }
                    }
                    return .swallow
                }
            }
    }
    func stop() {
        delivery.stop()
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil; subscription = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers = []
        lockObservers.forEach(DistributedNotificationCenter.default().removeObserver); lockObservers = []
        state.lock.withLock { state.policy.invalidate(retainConsumed: false); state.policy.foreground(nil) }
        status = "Button remapping is off."
    }
    private static func identity(_ app: NSRunningApplication?) -> MouseRemapApp? {
        guard let app, app.activationPolicy == .regular, !app.isTerminated,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = app.bundleIdentifier, let launch = app.launchDate?.timeIntervalSinceReferenceDate, launch.isFinite else { return nil }
        return .init(id: id, pid: app.processIdentifier, launched: launch)
    }
    private func updateForeground() {
        let app = !sleeping && !locked && Self.consoleUnlocked() ? Self.identity(NSWorkspace.shared.frontmostApplication) : nil
        state.lock.withLock { state.policy.foreground(app) }
    }
    private func validate(_ request: MouseRemapRequest) -> Bool {
        guard !sleeping, !locked, AXIsProcessTrusted(), !IsSecureEventInputEnabled(), Self.consoleUnlocked(),
              Self.identity(NSWorkspace.shared.frontmostApplication) == request.app,
              !AppLockManager.shared.isLocked,
              !NSApp.windows.contains(where: { $0.isVisible && $0.level.rawValue >= NSWindow.Level.screenSaver.rawValue }) else { return false }
        return state.lock.withLock { state.policy.accepts(request, now: ProcessInfo.processInfo.systemUptime) }
    }
    private static func consoleUnlocked() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any], session[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
        return !(session["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }
    private nonisolated static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
    private nonisolated static func resolve(_ request: MouseRemapRequest) -> MouseAXSelection? {
        let root = AXUIElementCreateApplication(request.app.pid)
        AXUIElementSetMessagingTimeout(root, 0.04)
        guard let menu: AXUIElement = attribute(root, kAXMenuBarAttribute) else { return nil }
        let result = MouseMenuSearch.find(menu, shortcut: request.command.shortcut, now: { ProcessInfo.processInfo.systemUptime }, children: { node in
            AXUIElementSetMessagingTimeout(node, 0.04)
            return attribute(node, kAXChildrenAttribute)
        }, command: { node in
            AXUIElementSetMessagingTimeout(node, 0.04)
            guard let character: String = attribute(node, kAXMenuItemCmdCharAttribute), !character.isEmpty,
                  let modifiers: Int = attribute(node, kAXMenuItemCmdModifiersAttribute),
                  attribute(node, kAXEnabledAttribute) as Bool? == true else { return nil }
            return .init(character: character.uppercased(), modifiers: modifiers)
        })
        return result.map { MouseAXSelection(element: $0) }
    }
}
#endif
