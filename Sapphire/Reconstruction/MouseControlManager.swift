#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine

private final class MouseScrollState: @unchecked Sendable {
    struct Configuration {
        var enabled = false
        var vertical = false
        var horizontal = false
        var speed = 1.0
        var excluded: Set<String> = []
    }
    let lock = NSLock()
    var config = Configuration()
    var appID: String?
    var pid: pid_t = 0
}

@MainActor
final class MouseControlManager {
    static let shared = MouseControlManager()
    private let state = MouseScrollState()
    private var subscription: AnyCancellable?
    private var tap: GlobalEventTap.Token?
    private var observers: [NSObjectProtocol] = []
    private init() {}
    func start() {
        guard subscription == nil else { return }
        let state = state
        func updateApp(_ app: NSRunningApplication?) {
            state.lock.withLock {
                state.appID = app?.activationPolicy == .regular ? app?.bundleIdentifier : nil
                state.pid = app?.processIdentifier ?? 0
            }
        }
        updateApp(NSWorkspace.shared.frontmostApplication)
        subscription = SettingsModel.shared.$settings.sink { settings in
            state.lock.withLock {
                state.config = .init(enabled: settings.mouseControlEnabled, vertical: settings.mouseInvertScroll,
                    horizontal: settings.mouseInvertHorizontalScroll, speed: settings.mouseScrollSpeed,
                    excluded: Set(settings.mouseExcludedAppBundleIDs))
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { updateApp(note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { updateApp(nil) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { updateApp(NSWorkspace.shared.frontmostApplication) }
        })
        tap = GlobalEventTap.shared.register(name: "FOSSMouseWheel", mask: 1 << CGEventType.scrollWheel.rawValue,
            priority: EventTapPriority.transform) { _, event in
                let snapshot = state.lock.withLock { (state.config, state.appID, state.pid) }
                let (config, appID, pid) = snapshot
                guard config.enabled, let appID, !config.excluded.contains(appID) else { return .pass }
                let target = event.getIntegerValueField(.eventTargetUnixProcessID)
                guard target == 0 || target == Int64(pid) else { return .pass }
                MouseScrollEventTransform.apply(to: event, speed: config.speed, vertical: config.vertical, horizontal: config.horizontal)
                return .pass
            }
    }
    func shutdown() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        subscription = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
    }
    // No persistent system preferences are changed by this implementation.
    func restoreSystemSettings() { shutdown() }
}
#endif
