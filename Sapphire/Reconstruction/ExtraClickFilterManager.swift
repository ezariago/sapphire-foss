#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine

private final class MouseClickFilterState: @unchecked Sendable {
    struct Configuration: Equatable { let enabled: Bool; let interval: Double; let excluded: Set<String> }
    let lock = NSLock()
    var configuration = Configuration(enabled: false, interval: 0.04, excluded: [])
    var appID = ""
    var policy = MouseClickBouncePolicy()
}

@MainActor
final class ExtraClickFilterManager {
    static let shared = ExtraClickFilterManager()
    private let state = MouseClickFilterState()
    private var subscription: AnyCancellable?
    private var tap: GlobalEventTap.Token?
    private var observers: [NSObjectProtocol] = []
    private init() {}
    func start() {
        guard subscription == nil else { return }
        let state = state
        state.lock.withLock { state.appID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "" }
        subscription = SettingsModel.shared.$settings.sink { settings in
            let config = MouseClickFilterState.Configuration(enabled: settings.mouseExtraClickFilterEnabled,
                interval: settings.mouseExtraClickFilterInterval, excluded: Set(settings.mouseExcludedAppBundleIDs))
            state.lock.withLock {
                if config != state.configuration { state.configuration = config; state.policy.reset() }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
            state.lock.withLock { state.appID = id; state.policy.reset() }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in state.lock.withLock { state.policy.reset() } })
        }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = GlobalEventTap.shared.register(name: "FOSSExtraClickFilter", mask: mask, priority: EventTapPriority.filter,
            reset: { state.lock.withLock { state.policy.reset() } }) { type, event in
                state.lock.withLock {
                    let config = state.configuration
                    guard config.enabled, !config.excluded.contains(state.appID) else { return .pass }
                    let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
                    let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).rawValue
                    let allowed: Bool
                    switch type {
                    case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                        allowed = state.policy.down(button, at: event.location, modifiers: modifiers,
                            now: ProcessInfo.processInfo.systemUptime, interval: config.interval)
                    case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                        allowed = state.policy.up(button, at: event.location, modifiers: modifiers, now: ProcessInfo.processInfo.systemUptime)
                    case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: allowed = state.policy.drag(button)
                    default: return .pass
                    }
                    return allowed ? .pass : .swallow
                }
            }
    }
    func shutdown() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        subscription = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
        state.lock.withLock { state.policy.reset() }
    }
}
#endif
