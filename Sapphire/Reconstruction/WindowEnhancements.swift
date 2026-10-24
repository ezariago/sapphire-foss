#if !SAPPHIRE_FULL_BUILD
import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit
import SwiftUI

struct SapphireWindow: Identifiable {
    let id: String
    let app: NSRunningApplication
    let element: AXUIElement
    let title: String
    let windowID: CGWindowID?
}

@MainActor
final class SystemEnhanceWindowRegistry {
    static let shared = SystemEnhanceWindowRegistry()
    private var identities: [pid_t: [(AXUIElement, String)]] = [:]
    private init() {}
    func windows(for application: NSRunningApplication? = nil) -> [SapphireWindow] {
        guard AXIsProcessTrusted() else { return [] }
        let records = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = application.map { [$0] } ?? NSWorkspace.shared.runningApplications.sorted { $0.processIdentifier == activePID && $1.processIdentifier != activePID }
        let runningPIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        identities = identities.filter { runningPIDs.contains($0.key) }
        return apps.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }.flatMap { app -> [SapphireWindow] in
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            let elements: [AXUIElement] = Self.attribute(root, kAXWindowsAttribute) ?? []
            let previous = identities[app.processIdentifier] ?? []
            let current = elements.map { element in
                (element, previous.first(where: { CFEqual($0.0, element) })?.1 ?? UUID().uuidString)
            }
            identities[app.processIdentifier] = current
            let candidates = records.compactMap { record -> WindowPreviewCandidate? in
                guard (record[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                      (record[kCGWindowLayer as String] as? Int) == 0,
                      let id = (record[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
                let bounds = (record[kCGWindowBounds as String] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
                return WindowPreviewCandidate(id: id, title: record[kCGWindowName as String] as? String, bounds: bounds)
            }
            return current.compactMap { element, identity in
                AXUIElementSetMessagingTimeout(element, 0.15)
                let role: String = Self.attribute(element, kAXRoleAttribute) ?? ""
                guard role == kAXWindowRole else { return nil }
                let title: String = Self.attribute(element, kAXTitleAttribute) ?? app.localizedName ?? "Window"
                let number = WindowPreviewMatcher.match(title: title, bounds: Self.bounds(element), candidates: candidates)
                let record = number.flatMap { number in records.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == number } }
                if !SettingsModel.shared.current.systemEnhanceSwitcherIncludeOtherSpaces,
                   let visible = record?[kCGWindowIsOnscreen as String] as? Bool, !visible {
                    let minimized: Bool = Self.attribute(element, kAXMinimizedAttribute) ?? false
                    if !minimized { return nil }
                }
                return SapphireWindow(id: "\(app.processIdentifier)-\(identity)", app: app, element: element, title: title, windowID: number)
            }
        }
    }
    private static func bounds(_ element: AXUIElement) -> CGRect? {
        guard let position: AXValue = attribute(element, kAXPositionAttribute),
              let size: AXValue = attribute(element, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    func focusedWindowID(for app: NSRunningApplication, in windows: [SapphireWindow]) -> String? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.15)
        guard let focused: AXUIElement = Self.attribute(root, kAXFocusedWindowAttribute) else { return nil }
        return windows.first { CFEqual($0.element, focused) }?.id
    }
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
    func activate(_ window: SapphireWindow) {
        guard !window.app.isTerminated else { return }
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        window.app.activate()
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(window.app.processIdentifier), kAXFocusedWindowAttribute as CFString, window.element)
    }
    func minimize(_ window: SapphireWindow) {
        AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    }
    func close(_ window: SapphireWindow) {
        if let button: AXUIElement = Self.attribute(window.element, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }
}

private final class WindowPickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class WindowPickerState: ObservableObject {
    @Published var selected = 0
    @Published var windows: [SapphireWindow] = []
    var choose: (SapphireWindow) -> Void = { _ in }
    var cancel: () -> Void = {}
}

private struct WindowThumbnail: View {
    let window: SapphireWindow
    var enhanced = false
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                VStack {
                    Image(nsImage: window.app.icon ?? NSImage()).resizable().frame(width: 40, height: 40)
                    Text(CGPreflightScreenCaptureAccess() ? "Preview unavailable" : "Allow Screen Recording for previews")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: enhanced ? 280 : 190, height: enhanced ? 160 : 110)
        .task(id: window.id) {
            guard CGPreflightScreenCaptureAccess(), let number = window.windowID else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let target = content.windows.first(where: { $0.windowID == number }) else { return }
                let filter = SCContentFilter(desktopIndependentWindow: target)
                let config = SCStreamConfiguration()
                config.width = enhanced ? 560 : 380
                config.height = enhanced ? 320 : 220
                config.showsCursor = false
                let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                guard !Task.isCancelled else { return }
                image = NSImage(cgImage: cgImage, size: .zero)
            } catch { image = nil }
        }
    }
}

private struct WindowPickerView: View {
    @ObservedObject var state: WindowPickerState
    let title: String
    let layout: SEPreviewLayout
    let enhanced: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Close", action: state.cancel).keyboardShortcut(.cancelAction)
            }
            if state.windows.isEmpty {
                Text(AXIsProcessTrusted() ? "No accessible windows." : "Allow Accessibility in System Settings to list and activate windows.")
                    .foregroundStyle(.secondary).padding()
            }
            ScrollViewReader { proxy in
                Group {
                    if layout == .carousel {
                        ScrollView(.horizontal) { LazyHStack(alignment: .top, spacing: 12) { cards } }
                    } else if layout == .list {
                        ScrollView { LazyVStack(alignment: .leading, spacing: 8) { cards } }
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: enhanced ? 300 : 210))], spacing: 12) { cards }
                        }
                    }
                }
                .onChange(of: state.selected, initial: true) { _, index in
                    if state.windows.indices.contains(index) { proxy.scrollTo(state.windows[index].id, anchor: .center) }
                }
            }
        }
        .padding(18)
        .frame(width: 700, height: 430)
        .background(.regularMaterial)
    }
    private var cards: some View {
        ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
            VStack(alignment: .leading, spacing: 6) {
                Button { state.choose(window) } label: {
                    Group {
                        if layout == .list {
                            HStack {
                                Image(nsImage: window.app.icon ?? NSImage()).resizable().frame(width: 28, height: 28)
                                VStack(alignment: .leading) {
                                    Text(window.app.localizedName ?? "Application").font(.caption.bold())
                                    Text(window.title).font(.caption).lineLimit(1)
                                }
                                Spacer()
                            }.frame(maxWidth: .infinity)
                        } else {
                            VStack(alignment: .leading) {
                                WindowThumbnail(window: window, enhanced: enhanced)
                                Text(window.app.localizedName ?? "Application").font(.caption.bold())
                                Text(window.title).font(.caption).lineLimit(1)
                            }.frame(width: enhanced ? 290 : 200)
                        }
                    }
                    .padding(8)
                    .background(index == state.selected ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                HStack {
                    Button("Minimize") { SystemEnhanceWindowRegistry.shared.minimize(window); state.cancel() }
                    Button("Close window") { SystemEnhanceWindowRegistry.shared.close(window); state.cancel() }
                }.font(.caption)
            }.id(window.id)
        }
    }
}

@MainActor
private final class WindowPicker {
    let state = WindowPickerState()
    private var panel: NSPanel?
    func show(windows: [SapphireWindow], title: String, near point: NSPoint? = nil, layout: SEPreviewLayout = .grid, enhanced: Bool = false, compact: Bool = false) {
        dismiss()
        state.windows = windows
        state.selected = 0
        state.cancel = { [weak self] in self?.dismiss() }
        state.choose = { [weak self] window in
            self?.dismiss()
            SystemEnhanceWindowRegistry.shared.activate(window)
        }
        let panel = WindowPickerPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 430), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WindowPickerView(state: state, title: title, layout: compact && windows.count > 6 ? .list : layout, enhanced: enhanced))
        if let point, let frame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame {
            if let placement = DockDisplayScopeState.panelFrame(size: panel.frame.size, near: point, visibleFrame: frame) {
                panel.setFrame(placement, display: false)
            }
        } else { panel.center() }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
    var isVisible: Bool { panel?.isVisible == true }
    func dismiss() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel?.close()
        panel = nil
        state.windows = []
    }
    func advance(reverse: Bool) { move(by: reverse ? -1 : 1) }
    func move(by offset: Int) {
        let count = state.windows.count
        if count > 0 { state.selected = ((state.selected + offset) % count + count) % count }
    }
    func closeSelection(quitApp: Bool) {
        guard state.windows.indices.contains(state.selected) else { dismiss(); return }
        let window = state.windows[state.selected]
        dismiss()
        if quitApp {
            guard !window.app.isTerminated, window.app.activationPolicy == .regular,
                  window.app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !["com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systempreferences", "com.apple.SystemSettings"].contains(window.app.bundleIdentifier ?? "") else { return }
            _ = window.app.terminate() // Respect save dialogs; never force termination.
        } else { SystemEnhanceWindowRegistry.shared.close(window) }
    }
    func commit() {
        guard state.windows.indices.contains(state.selected) else { dismiss(); return }
        state.choose(state.windows[state.selected])
    }
}

/// The event tap reads only a locked value snapshot; AX work happens on main.
private final class SwitcherKeyState: @unchecked Sendable {
    let lock = NSLock()
    var policy = WindowSwitcherKeyPolicy()
}

@MainActor
final class SystemEnhanceWindowSwitcher {
    static let shared = SystemEnhanceWindowSwitcher()
    private let picker = WindowPicker()
    private let keys = SwitcherKeyState()
    private var tap: GlobalEventTap.Token?
    private var settings: AnyCancellable?
    private init() {}
    func start() {
        guard settings == nil else { return }
        let keys = keys
        // Record configuration synchronously so queued input from an old policy
        // cannot reopen the picker after a disable/re-enable sequence.
        settings = SettingsModel.shared.$settings.sink { [weak self] config in
            let update = keys.lock.withLock { () -> (Bool, UInt64) in
                let changed = keys.policy.configure(enabled: config.systemEnhanceWindowSwitcherEnabled,
                    activation: config.systemEnhanceSwitcherActivationRaw,
                    columns: config.systemEnhanceWindowSwitcherLayout == .grid ? 3 : 1)
                return (changed, keys.policy.epoch)
            }
            if update.0 {
                DispatchQueue.main.async {
                    guard keys.lock.withLock({ keys.policy.epoch == update.1 }) else { return }
                    self?.picker.dismiss()
                }
            }
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        tap = GlobalEventTap.shared.register(name: "FOSSWindowSwitcher", mask: mask, priority: EventTapPriority.shortcut, reset: { [weak self] in
            let epoch = keys.lock.withLock { keys.policy.reset(); return keys.policy.epoch }
            DispatchQueue.main.async {
                guard keys.lock.withLock({ keys.policy.epoch == epoch }) else { return }
                self?.picker.dismiss()
            }
        }) { [weak self] type, event in
            let effect = keys.lock.withLock { () -> (WindowSwitcherKeyPolicy.Action, UInt64)? in
                let action: WindowSwitcherKeyPolicy.Action?
                let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
                if type == .flagsChanged {
                    action = keys.policy.flagsChanged(command: event.flags.contains(.maskCommand), option: event.flags.contains(.maskAlternate))
                } else if type == .keyUp { action = keys.policy.keyUp(code) }
                else if type == .keyDown {
                    action = keys.policy.keyDown(code, command: event.flags.contains(.maskCommand), option: event.flags.contains(.maskAlternate),
                        control: event.flags.contains(.maskControl), shift: event.flags.contains(.maskShift))
                } else { action = nil }
                return action.map { ($0, keys.policy.epoch) }
            }
            guard let (action, epoch) = effect else { return .pass }
            if action != .suppress {
                // The event tap is serial. Main-queue FIFO keeps rapid Tab/release
                // events ordered while AX work is pending.
                DispatchQueue.main.async {
                    guard let self, keys.lock.withLock({ keys.policy.enabled && keys.policy.epoch == epoch }) else { return }
                    switch action {
                    case .commit: self.picker.commit()
                    case .cancel, .cancelAndPass: self.picker.dismiss()
                    case .move(let offset): self.picker.move(by: offset)
                    case .close: self.picker.closeSelection(quitApp: false)
                    case .quit: self.picker.closeSelection(quitApp: true)
                    case .advance(let reverse):
                        if !self.picker.isVisible {
                            self.picker.show(windows: SystemEnhanceWindowRegistry.shared.windows(), title: "Windows", layout: SettingsModel.shared.current.systemEnhanceWindowSwitcherLayout)
                        }
                        self.picker.advance(reverse: reverse)
                    case .suppress: break
                    }
                }
            }
            return type == .flagsChanged || action == .cancelAndPass ? .pass : .swallow
        }
    }
    func dismiss() { picker.dismiss(); keys.lock.withLock { keys.policy.reset() } }
}

@MainActor
final class SystemEnhanceDockPreviewController {
    static let shared = SystemEnhanceDockPreviewController()
    private let picker = WindowPicker()
    private var timer: Timer?
    private var clickMonitor: Any?
    private var scopeSubscription: AnyCancellable?
    private var hovered: pid_t?
    private var hoverStarted = Date.distantPast
    private var lastDockHover = Date.distantPast
    private init() {}
    func start() {
        guard timer == nil else { return }
        DockDisplayScope.shared.start()
        scopeSubscription = DockDisplayScope.shared.$revision.sink { [weak self] _ in
            self?.picker.dismiss(); self?.hovered = nil; self?.hoverStarted = .distantPast; self?.lastDockHover = .distantPast
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.otherMouseDown, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleClick(event) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func handleClick(_ event: NSEvent) {
        let config = SettingsModel.shared.current
        let matches = config.systemEnhancePreviewTriggerRaw == "middleClick" && event.type == .otherMouseDown && event.buttonNumber == 2
            || config.systemEnhancePreviewTriggerRaw == "modifierClick" && event.type == .leftMouseDown && event.modifierFlags.intersection([.command, .control, .option, .shift]) == .option
        guard matches, config.systemEnhanceDockPreviewsEnabled, AXIsProcessTrusted(),
              DockDisplayScope.shared.ticket(at: NSEvent.mouseLocation) != nil,
              let app = DockElementUnderPointer.application() else { return }
        hovered = app.processIdentifier
        lastDockHover = .now
        show(app, config: config)
    }
    private func show(_ app: NSRunningApplication, config: Settings) {
        let point = NSEvent.mouseLocation
        guard SettingsModel.shared.current.systemEnhanceDockPreviewsEnabled,
              DockScopeConfiguration(config) == DockScopeConfiguration(SettingsModel.shared.current),
              let ticket = DockDisplayScope.shared.ticket(at: point) else { return }
        let windows = SystemEnhanceWindowRegistry.shared.windows(for: app)
        guard DockDisplayScope.shared.accepts(ticket) else { return }
        picker.show(windows: windows, title: app.localizedName ?? "Windows", near: point,
                    layout: config.systemEnhancePreviewLayout, enhanced: config.systemEnhanceEnhancedPreviewsEnabled,
                    compact: config.systemEnhanceCompactPreviewEnabled)
    }
    private func tick() {
        let config = SettingsModel.shared.current
        guard config.systemEnhanceDockPreviewsEnabled, AXIsProcessTrusted(),
              DockDisplayScope.shared.ticket(at: NSEvent.mouseLocation) != nil else { picker.dismiss(); hovered = nil; return }
        // Keep a visible panel usable while the pointer moves from the Dock to it.
        if picker.isVisible && NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) && $0.level == .floating }) { return }
        guard let app = DockElementUnderPointer.application() else {
            if Date().timeIntervalSince(lastDockHover) > 0.7 { hovered = nil; picker.dismiss() }
            return
        }
        lastDockHover = .now
        if hovered != app.processIdentifier {
            hovered = app.processIdentifier
            hoverStarted = .now
            picker.dismiss()
        }
        if config.systemEnhancePreviewTrigger == .hover, !picker.isVisible,
           Date().timeIntervalSince(hoverStarted) >= max(0.1, config.systemEnhancePreviewDelay) {
            show(app, config: config)
        }
    }
    func dismiss() {
        timer?.invalidate(); timer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }; clickMonitor = nil
        scopeSubscription = nil
        picker.dismiss(); hovered = nil
    }
}

@MainActor
enum DockElementUnderPointer {
    static func application() -> NSRunningApplication? {
        guard AXIsProcessTrusted(), let point = CGEvent(source: nil)?.location else { return nil }
        let root = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root, 0.1)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(root, Float(point.x), Float(point.y), &hit) == .success, var element = hit else { return nil }
        for _ in 0..<5 {
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success, NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock" else { return nil }
            if let url: URL = SystemEnhanceWindowRegistry.attribute(element, kAXURLAttribute),
               let id = Bundle(url: url)?.bundleIdentifier {
                return NSRunningApplication.runningApplications(withBundleIdentifier: id).first
            }
            guard let parent: AXUIElement = SystemEnhanceWindowRegistry.attribute(element, kAXParentAttribute) else { break }
            element = parent
        }
        return nil
    }
}

@MainActor
final class SystemEnhanceDockClicks {
    static let shared = SystemEnhanceDockClicks()
    private var monitor: Any?
    private var cycles: [pid_t: WindowCyclePolicy] = [:]
    private init() {}
    func start() {
        guard monitor == nil else { return }
        DockDisplayScope.shared.start()
        // Observe mouse-down before the Dock activates a different application.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { event in
            MainActor.assumeIsolated {
                let config = SettingsModel.shared.current
                guard config.systemEnhanceDockClicksEnabled,
                      let scopeTicket = DockDisplayScope.shared.ticket(at: NSEvent.mouseLocation),
                      !(config.systemEnhanceDockPreviewsEnabled && config.systemEnhancePreviewTrigger == .modifierClick && event.modifierFlags.intersection([.command, .control, .option, .shift]) == .option),
                      let app = DockElementUnderPointer.application(), let id = app.bundleIdentifier,
                      config.isDockClickEnabled(for: id), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                let action = config.systemEnhanceDockClickActionRaw
                let windows = action == "cycle" ? SystemEnhanceWindowRegistry.shared.windows(for: app) : []
                let focused = action == "cycle" ? SystemEnhanceWindowRegistry.shared.focusedWindowID(for: app, in: windows) : nil
                let livePIDs = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
                self.cycles = self.cycles.filter { livePIDs.contains($0.key) }
                let selected = action == "cycle" ? self.cycles[app.processIdentifier, default: WindowCyclePolicy()].next(windows: windows.map(\.id), focused: focused) : nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    let current = SettingsModel.shared.current
                    guard DockDisplayScope.shared.accepts(scopeTicket),
                          current.systemEnhanceDockClicksEnabled, current.isDockClickEnabled(for: id),
                          current.systemEnhanceDockClickActionRaw == action, !app.isTerminated,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                    if action == "hide" { app.hide() }
                    else {
                        let windows = SystemEnhanceWindowRegistry.shared.windows(for: app)
                        if action == "cycle" {
                            if let window = windows.first(where: { $0.id == selected }) { SystemEnhanceWindowRegistry.shared.activate(window) }
                        } else if action == "minimize" { windows.forEach { SystemEnhanceWindowRegistry.shared.minimize($0) } }
                    }
                }
            }
        }
    }
    func stopMonitoring() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil; cycles.removeAll() }
}
#endif
