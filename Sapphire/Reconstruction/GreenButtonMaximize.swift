#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices

private final class GreenButtonHit: @unchecked Sendable {
    let lock = NSLock()
    var window: AXUIElement?
    var pid: pid_t = 0
    var point = CGPoint.zero
    var updated: TimeInterval = 0
    var suppressUp = false
}

@MainActor
final class SystemEnhanceGreenMaximize {
    static let shared = SystemEnhanceGreenMaximize()
    private let hit = GreenButtonHit()
    private var timer: Timer?
    private var tap: GlobalEventTap.Token?
    private var previousFrames: [String: (CGPoint, CGSize)] = [:]
    private init() {}
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHit() }
        }
        let hit = hit
        tap = GlobalEventTap.shared.register(name: "FOSSGreenMaximize", mask: (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue), priority: EventTapPriority.transform) { [weak self] type, event in
            let target: (AXUIElement?, pid_t, Bool) = hit.lock.withLock {
                if type == .leftMouseUp {
                    let swallow = hit.suppressUp
                    hit.suppressUp = false
                    return (nil, 0, swallow)
                }
                guard let window = hit.window, ProcessInfo.processInfo.systemUptime - hit.updated < 0.25,
                      hypot(event.location.x - hit.point.x, event.location.y - hit.point.y) < 5,
                      event.flags.intersection([.maskAlternate, .maskControl, .maskShift]).isEmpty else { return (nil, 0, false) }
                hit.suppressUp = true
                return (window, hit.pid, true)
            }
            if let window = target.0 {
                Task { @MainActor in self?.toggle(window, pid: target.1) }
            }
            return target.2 ? .swallow : .pass
        }
    }
    private func updateHit() {
        let config = SettingsModel.shared.current
        var target: AXUIElement?
        var pid: pid_t = 0
        let point = CGEvent(source: nil)?.location ?? .zero
        if config.systemEnhanceGreenMaximizeEnabled, AXIsProcessTrusted() {
            let root = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(root, 0.1)
            var element: AXUIElement?
            if AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &element) == .success, let element,
               AXUIElementGetPid(element, &pid) == .success,
               let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier,
               !config.systemEnhanceGreenMaximizeExcludedApps.contains(id) {
                let role: String = SystemEnhanceWindowRegistry.attribute(element, kAXSubroleAttribute) ?? ""
                if role == "AXZoomButton" || role == "AXFullScreenButton" {
                    target = SystemEnhanceWindowRegistry.attribute(element, kAXWindowAttribute)
                    if let window = target {
                        let fullScreen: Bool = SystemEnhanceWindowRegistry.attribute(window, "AXFullScreen") ?? false
                        if fullScreen { target = nil } // Preserve native exit-full-screen.
                    }
                }
            }
        }
        hit.lock.withLock { hit.window = target; hit.pid = pid; hit.point = point; hit.updated = ProcessInfo.processInfo.systemUptime }
    }
    private func toggle(_ window: AXUIElement, pid: pid_t) {
        let config = SettingsModel.shared.current
        guard config.systemEnhanceGreenMaximizeEnabled, AXIsProcessTrusted(),
              let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier,
              !config.systemEnhanceGreenMaximizeExcludedApps.contains(id), let primary = NSScreen.screens.first,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
              let oldPosition: AXValue = SystemEnhanceWindowRegistry.attribute(window, kAXPositionAttribute),
              let oldSize: AXValue = SystemEnhanceWindowRegistry.attribute(window, kAXSizeAttribute) else { return }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(oldPosition, .cgPoint, &origin), AXValueGetValue(oldSize, .cgSize, &size) else { return }
        let key = "\(pid)-\(CFHash(window))"
        let frame = screen.visibleFrame
        let maximized = abs(size.width - frame.width) < 4 && abs(size.height - frame.height) < 4
        if maximized, let previous = previousFrames.removeValue(forKey: key) {
            origin = previous.0; size = previous.1
        } else {
            previousFrames[key] = (origin, size)
            origin = CGPoint(x: frame.minX, y: primary.frame.maxY - frame.maxY)
            size = frame.size
        }
        if let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        }
        if previousFrames.count > 200 { previousFrames.removeAll() }
    }
    func stopMonitoring() {
        timer?.invalidate(); timer = nil
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        hit.lock.withLock { hit.window = nil; hit.suppressUp = false }
        previousFrames.removeAll()
    }
}
#endif
