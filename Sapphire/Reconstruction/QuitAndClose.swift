#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Combine

private final class QuitProtectionConfiguration: @unchecked Sendable {
    let lock = NSLock()
    var settings: Settings?
    var appID = ""
    var policy = QuitProtectionPolicy()
}

@MainActor
final class SystemEnhanceQuitProtection {
    static let shared = SystemEnhanceQuitProtection()
    private let state = QuitProtectionConfiguration()
    private var tap: GlobalEventTap.Token?
    private var subscription: AnyCancellable?
    private var observer: NSObjectProtocol?
    private init() {}
    func start() {
        guard subscription == nil else { return }
        subscription = SettingsModel.shared.$settings.receive(on: RunLoop.main).sink { [weak self] settings in
            guard let self else { return }
            self.state.lock.withLock { self.state.settings = settings; self.state.policy.reset() }
        }
        updateActiveApp()
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.updateActiveApp() }
        }
        let state = state
        tap = GlobalEventTap.shared.register(name: "FOSSQuitProtection", mask: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue), priority: EventTapPriority.filter) { type, event in
            state.lock.withLock {
                guard let settings = state.settings, settings.systemEnhanceQuitProtectionEnabled,
                      !settings.systemEnhanceQuitProtectionExcludedApps.contains(state.appID) else { return .pass }
                if type == .flagsChanged {
                    if !event.flags.contains(.maskCommand) { state.policy.releaseHeldKeys() }
                    return .pass
                }
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let quit = code == 12 && settings.systemEnhanceQuitProtectionProtectQuit
                let close = code == 13 && settings.systemEnhanceQuitProtectionProtectClose
                guard quit || close else { return .pass }
                let key = "\(state.appID):\(code)"
                if type == .keyUp { state.policy.keyUp(key: key); return .pass }
                guard event.flags.contains(.maskCommand) else { return .pass }
                let extraFlag: CGEventFlags
                switch settings.systemEnhanceQuitProtectionExtraModifierRaw {
                case "shift": extraFlag = .maskShift
                case "control": extraFlag = .maskControl
                default: extraFlag = .maskAlternate
                }
                let closeMode = settings.systemEnhanceQuitProtectionCloseModeRaw
                let mode = close && !closeMode.isEmpty ? closeMode : settings.systemEnhanceQuitProtectionModeRaw
                if event.flags.contains(.maskControl) && !(mode == "extraModifier" && extraFlag == .maskControl) { return .pass }
                let allow = state.policy.keyDown(key: key, mode: mode,
                    now: ProcessInfo.processInfo.systemUptime,
                    holdInterval: close ? settings.systemEnhanceQuitProtectionCloseHoldInterval : settings.systemEnhanceQuitProtectionHoldInterval,
                    doubleInterval: close ? settings.systemEnhanceQuitProtectionCloseDoublePressInterval : settings.systemEnhanceQuitProtectionDoublePressInterval,
                    isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    hasExtraModifier: event.flags.contains(extraFlag))
                return allow ? .pass : .swallow
            }
        }
    }
    private func updateActiveApp() {
        let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        state.lock.withLock { state.appID = id; state.policy.reset() }
    }
    func removeTap() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        subscription = nil
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; observer = nil
        state.lock.withLock { state.policy.reset() }
    }
}

@MainActor
final class SystemEnhanceAutoQuit {
    static let shared = SystemEnhanceAutoQuit()
    private var timer: Timer?
    private var lastHadWindows: Set<pid_t> = []
    private var emptySince: [pid_t: Date] = [:]
    private init() {}
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }
    private func check() {
        let config = SettingsModel.shared.current
        guard config.systemEnhanceAutoQuitEnabled, AXIsProcessTrusted() else { lastHadWindows.removeAll(); emptySince.removeAll(); return }
        let apps = NSWorkspace.shared.runningApplications
        let running = Set(apps.map(\.processIdentifier))
        lastHadWindows.formIntersection(running)
        emptySince = emptySince.filter { running.contains($0.key) }
        for app in apps {
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier,
                  id != Bundle.main.bundleIdentifier,
                  !["com.apple.finder", "com.apple.systempreferences", "com.apple.SystemSettings"].contains(id),
                  !config.systemEnhanceAutoQuitExcludedApps.contains(id), !app.isTerminated else { continue }
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            // A denied/failed AX query is never evidence that the app is empty.
            guard let windows: [AXUIElement] = SystemEnhanceWindowRegistry.attribute(root, kAXWindowsAttribute) else { continue }
            if !windows.isEmpty {
                lastHadWindows.insert(app.processIdentifier)
                emptySince[app.processIdentifier] = nil
            } else if lastHadWindows.contains(app.processIdentifier) {
                if let since = emptySince[app.processIdentifier], Date().timeIntervalSince(since) >= 3 {
                    _ = app.terminate() // Respect document-save dialogs; never force-quit here.
                    lastHadWindows.remove(app.processIdentifier)
                    emptySince[app.processIdentifier] = nil
                } else if emptySince[app.processIdentifier] == nil { emptySince[app.processIdentifier] = .now }
            }
        }
    }
    func stopObserving() { timer?.invalidate(); timer = nil; lastHadWindows.removeAll(); emptySince.removeAll() }
}

#endif
