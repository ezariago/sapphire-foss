#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine

@MainActor
final class FocusFollowsMouseManager {
    static let shared = FocusFollowsMouseManager()
    private var timer: Timer?
    private var globalKeys: Any?
    private var localKeys: Any?
    private var subscription: AnyCancellable?
    private var lifecycle: [NSObjectProtocol] = []
    private var policy = HoverFocusPolicy()
    private var hovered: AXUIElement?
    private var identity = UUID().uuidString
    private struct Configuration: Equatable { let enabled: Bool; let delay: Double; let excluded: Set<String> }
    private init() {}
    func start() {
        guard timer == nil else { return }
        subscription = SettingsModel.shared.$settings
            .map { Configuration(enabled: $0.mouseFocusFollowsEnabled, delay: $0.mouseFocusFollowsDelay, excluded: Set($0.mouseExcludedAppBundleIDs)) }
            .removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in self?.resetHover() }
        globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.resetHover() }
        }
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.resetHover() }
            return event
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.didActivateApplicationNotification] {
            lifecycle.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resetHover() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func resetHover() { policy.reset(); hovered = nil }
    private func tick() {
        let config = SettingsModel.shared.current
        guard config.mouseFocusFollowsEnabled, AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              NSEvent.pressedMouseButtons == 0,
              NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let front = NSWorkspace.shared.frontmostApplication, front.activationPolicy == .regular,
              !config.mouseExcludedAppBundleIDs.contains(front.bundleIdentifier ?? ""),
              let point = CGEvent(source: nil)?.location else { resetHover(); return }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit, let window = windowAncestor(hit) else { resetHover(); return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window, &pid) == .success, pid != ProcessInfo.processInfo.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular, !app.isTerminated,
              !config.mouseExcludedAppBundleIDs.contains(app.bundleIdentifier ?? ""),
              (SystemEnhanceWindowRegistry.attribute(window, kAXMinimizedAttribute) as Bool?) != true else { resetHover(); return }
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.1)
        if front.processIdentifier == pid, let focused: AXUIElement = SystemEnhanceWindowRegistry.attribute(root, kAXFocusedWindowAttribute), CFEqual(focused, window) {
            resetHover(); return
        }
        if hovered.map({ CFEqual($0, window) }) != true { hovered = window; identity = UUID().uuidString }
        guard policy.observe(target: identity, now: ProcessInfo.processInfo.systemUptime, delay: config.mouseFocusFollowsDelay) else { return }
        let current = SettingsModel.shared.current
        guard current.mouseFocusFollowsEnabled, AXIsProcessTrusted(), !IsSecureEventInputEnabled(),
              NSEvent.pressedMouseButtons == 0,
              NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              !current.mouseExcludedAppBundleIDs.contains(app.bundleIdentifier ?? ""),
              !current.mouseExcludedAppBundleIDs.contains(front.bundleIdentifier ?? ""), !app.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier,
              CGEvent(source: nil)?.location == point else { resetHover(); return }
        app.activate()
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(root, kAXFocusedWindowAttribute as CFString, window)
    }
    private func windowAncestor(_ hit: AXUIElement) -> AXUIElement? {
        var element = hit
        for _ in 0..<12 {
            AXUIElementSetMessagingTimeout(element, 0.1)
            let role: String = SystemEnhanceWindowRegistry.attribute(element, kAXRoleAttribute) ?? ""
            if role == kAXWindowRole { return element }
            if [kAXMenuRole, kAXMenuBarRole, kAXMenuItemRole].contains(role) { return nil }
            guard let parent: AXUIElement = SystemEnhanceWindowRegistry.attribute(element, kAXParentAttribute) else { return nil }
            element = parent
        }
        return nil
    }
    func removeMonitors() {
        timer?.invalidate(); timer = nil; subscription = nil
        if let globalKeys { NSEvent.removeMonitor(globalKeys) }; globalKeys = nil
        if let localKeys { NSEvent.removeMonitor(localKeys) }; localKeys = nil
        lifecycle.forEach(NSWorkspace.shared.notificationCenter.removeObserver); lifecycle.removeAll()
        resetHover()
    }
}
#endif
