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
    private init() {}
    func windows(for application: NSRunningApplication? = nil) -> [SapphireWindow] {
        guard AXIsProcessTrusted() else { return [] }
        let records = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = application.map { [$0] } ?? NSWorkspace.shared.runningApplications.sorted { $0.processIdentifier == activePID && $1.processIdentifier != activePID }
        return apps.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }.flatMap { app -> [SapphireWindow] in
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 0.15)
            let elements: [AXUIElement] = Self.attribute(root, kAXWindowsAttribute) ?? []
            return elements.enumerated().compactMap { index, element in
                let role: String = Self.attribute(element, kAXRoleAttribute) ?? ""
                guard role == kAXWindowRole else { return nil }
                let title: String = Self.attribute(element, kAXTitleAttribute) ?? app.localizedName ?? "Window"
                let record = records.first { ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && ($0[kCGWindowName as String] as? String) == title && ($0[kCGWindowLayer as String] as? Int) == 0 }
                let number = (record?[kCGWindowNumber as String] as? NSNumber)?.uint32Value
                if !SettingsModel.shared.current.systemEnhanceSwitcherIncludeOtherSpaces,
                   let visible = record?[kCGWindowIsOnscreen as String] as? Bool, !visible {
                    let minimized: Bool = Self.attribute(element, kAXMinimizedAttribute) ?? false
                    if !minimized { return nil }
                }
                return SapphireWindow(id: "\(app.processIdentifier)-\(number.map(String.init) ?? String(index))", app: app, element: element, title: title, windowID: number)
            }
        }
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
        .frame(width: 190, height: 110)
        .task(id: window.id) {
            guard CGPreflightScreenCaptureAccess(), let number = window.windowID else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let target = content.windows.first(where: { $0.windowID == number }) else { return }
                let filter = SCContentFilter(desktopIndependentWindow: target)
                let config = SCStreamConfiguration()
                config.width = 380
                config.height = 220
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
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210))], spacing: 12) {
                    ForEach(Array(state.windows.enumerated()), id: \.element.id) { index, window in
                        VStack(alignment: .leading, spacing: 6) {
                            Button { state.choose(window) } label: {
                                VStack(alignment: .leading) {
                                    WindowThumbnail(window: window)
                                    Text(window.app.localizedName ?? "Application").font(.caption.bold())
                                    Text(window.title).font(.caption).lineLimit(1)
                                }
                                .frame(width: 200)
                                .padding(8)
                                .background(index == state.selected ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                            HStack {
                                Button("Minimize") { SystemEnhanceWindowRegistry.shared.minimize(window); state.cancel() }
                                Button("Close window") { SystemEnhanceWindowRegistry.shared.close(window); state.cancel() }
                            }.font(.caption)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 700, height: 430)
        .background(.regularMaterial)
    }
}

@MainActor
private final class WindowPicker {
    let state = WindowPickerState()
    private var panel: NSPanel?
    func show(windows: [SapphireWindow], title: String, near point: NSPoint? = nil) {
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
        panel.contentView = NSHostingView(rootView: WindowPickerView(state: state, title: title))
        if let point, let frame = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: min(max(frame.minX, point.x - 350), frame.maxX - 700), y: min(max(frame.minY, point.y + 20), frame.maxY - 430)))
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
    func advance(reverse: Bool) {
        let count = state.windows.count
        if count > 0 { state.selected = (state.selected + (reverse ? count - 1 : 1)) % count }
    }
    func commit() {
        guard state.windows.indices.contains(state.selected) else { dismiss(); return }
        state.choose(state.windows[state.selected])
    }
}

/// The event tap reads only a locked value snapshot; AX work happens on main.
private final class SwitcherKeyState: @unchecked Sendable {
    let lock = NSLock()
    var enabled = false
    var activation = "both"
    var active = false
    var modifier: CGEventFlags = .maskAlternate
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
        settings = SettingsModel.shared.$settings.receive(on: RunLoop.main).sink { [weak self] config in
            guard let self else { return }
            self.keys.lock.withLock { self.keys.enabled = config.systemEnhanceWindowSwitcherEnabled; self.keys.activation = config.systemEnhanceSwitcherActivationRaw }
            if !config.systemEnhanceWindowSwitcherEnabled { self.dismiss() }
        }
        let keys = keys
        tap = GlobalEventTap.shared.register(name: "FOSSWindowSwitcher", mask: (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue), priority: EventTapPriority.shortcut) { [weak self] type, event in
            let action: Int = keys.lock.withLock {
                guard keys.enabled else { return 0 }
                if type == .flagsChanged, keys.active, !event.flags.contains(keys.modifier) { keys.active = false; return 2 }
                guard type == .keyDown else { return 0 }
                let key = event.getIntegerValueField(.keyboardEventKeycode)
                if key == 53, keys.active { keys.active = false; return 3 }
                guard key == 48, !event.flags.contains(.maskControl),
                      (keys.activation != "option" && event.flags.contains(.maskCommand)) || (keys.activation != "command" && event.flags.contains(.maskAlternate)) else { return 0 }
                keys.active = true
                keys.modifier = event.flags.contains(.maskCommand) ? .maskCommand : .maskAlternate
                return event.flags.contains(.maskShift) ? -1 : 1
            }
            guard action != 0 else { return .pass }
            Task { @MainActor in
                guard let self else { return }
                if action == 2 { self.picker.commit() }
                else if action == 3 { self.dismiss() }
                else {
                    if !self.picker.isVisible {
                        self.picker.show(windows: SystemEnhanceWindowRegistry.shared.windows(), title: "Windows")
                    }
                    self.picker.advance(reverse: action == -1)
                }
            }
            return type == .flagsChanged ? .pass : .swallow
        }
    }
    func dismiss() { picker.dismiss(); keys.lock.withLock { keys.active = false } }
}

@MainActor
final class SystemEnhanceDockPreviewController {
    static let shared = SystemEnhanceDockPreviewController()
    private let picker = WindowPicker()
    private var timer: Timer?
    private var hovered: pid_t?
    private var hoverStarted = Date.distantPast
    private var lastDockHover = Date.distantPast
    private init() {}
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func tick() {
        let config = SettingsModel.shared.current
        guard config.systemEnhanceDockPreviewsEnabled, AXIsProcessTrusted() else { picker.dismiss(); return }
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
        if !picker.isVisible && Date().timeIntervalSince(hoverStarted) >= max(0.1, config.systemEnhancePreviewDelay) {
            picker.show(windows: SystemEnhanceWindowRegistry.shared.windows(for: app), title: app.localizedName ?? "Windows", near: NSEvent.mouseLocation)
        }
    }
    func dismiss() { timer?.invalidate(); timer = nil; picker.dismiss(); hovered = nil }
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
    private init() {}
    func start() {
        guard monitor == nil else { return }
        // Observe mouse-down before the Dock activates a different application.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { _ in
            MainActor.assumeIsolated {
                let config = SettingsModel.shared.current
                guard config.systemEnhanceDockClicksEnabled,
                      let app = DockElementUnderPointer.application(), let id = app.bundleIdentifier,
                      config.isDockClickEnabled(for: id), NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                let action = config.systemEnhanceDockClickActionRaw
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard SettingsModel.shared.current.systemEnhanceDockClicksEnabled, !app.isTerminated else { return }
                    if action == "hide" { app.hide() }
                    else {
                        let windows = SystemEnhanceWindowRegistry.shared.windows(for: app)
                        if action == "cycle", let first = windows.first { SystemEnhanceWindowRegistry.shared.activate(first) }
                        else { windows.forEach { SystemEnhanceWindowRegistry.shared.minimize($0) } }
                    }
                }
            }
        }
    }
    func stopMonitoring() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
}
#endif
