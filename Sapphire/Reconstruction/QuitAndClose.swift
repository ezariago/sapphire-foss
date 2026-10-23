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
    private var policy = AutoQuitPolicy()
    private var configurationSubscription: AnyCancellable?
    private struct Configuration: Equatable { let enabled: Bool; let excluded: Set<String> }
    private var lifecycleObservers: [NSObjectProtocol] = []
    private init() {}
    func start() {
        guard timer == nil else { return }
        configurationSubscription = SettingsModel.shared.$settings
            .map { Configuration(enabled: $0.systemEnhanceAutoQuitEnabled, excluded: Set($0.systemEnhanceAutoQuitExcludedApps)) }
            .removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.policy.reset() }
        let center = NSWorkspace.shared.notificationCenter
        lifecycleObservers = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.policy.reset() }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
    }
    private func check() {
        let config = SettingsModel.shared.current
        guard config.systemEnhanceAutoQuitEnabled, AXIsProcessTrusted() else { policy.reset(); return }
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (NSRunningApplication, String, String)? in
            guard app.activationPolicy == .regular, !app.isTerminated,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  let id = app.bundleIdentifier, let launched = app.launchDate,
                  !["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systempreferences", "com.apple.SystemSettings"].contains(id),
                  !config.systemEnhanceAutoQuitExcludedApps.contains(id) else { return nil }
            return (app, id, "\(app.processIdentifier):\(launched.timeIntervalSinceReferenceDate)")
        }
        policy.retain(Set(apps.map { $0.2 }))
        for (app, id, key) in apps {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.1)
            let windows: [AXUIElement]? = SystemEnhanceWindowRegistry.attribute(root, kAXWindowsAttribute)
            let request = policy.observe(key, windowCount: windows?.count, now: ProcessInfo.processInfo.systemUptime)
            let current = SettingsModel.shared.current
            guard request, current.systemEnhanceAutoQuitEnabled, AXIsProcessTrusted(),
                  !current.systemEnhanceAutoQuitExcludedApps.contains(id), !app.isTerminated else { continue }
            _ = app.terminate() // Respect document-save dialogs; never force-quit here.
        }
    }
    func stopObserving() {
        timer?.invalidate(); timer = nil; policy.reset(); configurationSubscription = nil
        lifecycleObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        lifecycleObservers.removeAll()
    }
}

#endif
