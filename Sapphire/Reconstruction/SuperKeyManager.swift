#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine

private final class SuperKeyState: @unchecked Sendable {
    struct Configuration {
        var enabled = false
        var source = "rightCommand"
        var excluded: Set<String> = []
    }
    let lock = NSLock()
    var config = Configuration()
    var foreground: (id: String, pid: pid_t)?
}

@MainActor
final class SuperKeyManager {
    static let shared = SuperKeyManager()
    private let state = SuperKeyState()
    private var tap: GlobalEventTap.Token?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private init() {}
    func start() {
        guard subscription == nil else { return }
        let state = state
        func updateApp(_ app: NSRunningApplication?) {
            state.lock.withLock {
                if let app, app.activationPolicy == .regular, let id = app.bundleIdentifier {
                    state.foreground = (id, app.processIdentifier)
                } else { state.foreground = nil }
            }
        }
        updateApp(NSWorkspace.shared.frontmostApplication)
        subscription = SettingsModel.shared.$settings.sink { settings in
            state.lock.withLock {
                state.config = .init(enabled: settings.superKeyEnabled, source: settings.superKeyKeyRaw,
                    excluded: Set(settings.superKeyExcludedAppBundleIDs))
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
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
            .otherMouseDragged, .mouseMoved, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = GlobalEventTap.shared.register(name: "FOSSSuperKey", mask: mask, priority: EventTapPriority.filter - 10) { _, event in
            let (config, foreground) = state.lock.withLock { (state.config, state.foreground) }
            guard config.enabled, let foreground, !config.excluded.contains(foreground.id) else { return .pass }
            let target = event.getIntegerValueField(.eventTargetUnixProcessID)
            guard target == 0 || target == Int64(foreground.pid) else { return .pass }
            SuperKeyPolicy.apply(to: event, source: config.source)
            return .pass
        }
    }
    func stopMonitoring() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        subscription = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
    }
}
#endif
