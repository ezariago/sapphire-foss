#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI

private final class AppShieldPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A session-level privacy/focus shield. macOS login remains the security boundary.
@MainActor
final class AppBlocker {
    var isBlocked: (String) -> Bool = { _ in false }
    var makeShieldContent: (String, String) -> AnyView = { _, _ in AnyView(EmptyView()) }
    var shieldsAreKeyable = false
    var forceClosesOnActivation = false
    var shieldsOnlyWhenFrontmost = false
    var keepsShieldWhenNotFrontmost: (String) -> Bool = { _ in false }
    var onAppActivated: ((_ appName: String, _ bundleID: String, _ app: NSRunningApplication) -> Void)?
    private(set) var isBlocking = false
    private var shields: [String: [NSPanel]] = [:]
    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?
    private let screenFrames: () -> [NSRect]
    init(screenFrames: @escaping () -> [NSRect] = { NSScreen.screens.map(\.frame) }) {
        self.screenFrames = screenFrames
    }

    func setBlocking(_ enabled: Bool) {
        guard enabled != isBlocking else { refresh(); return }
        isBlocking = enabled
        if enabled {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    Task { @MainActor in
                        guard let self else { return }
                        if name == NSWorkspace.didActivateApplicationNotification,
                           let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                           let id = app.bundleIdentifier, self.shouldBlock(app) {
                            self.onAppActivated?(app.localizedName ?? id, id, app)
                            if self.forceClosesOnActivation {
                                AppShieldManager.forceClose(app, guard: self.isBlocking && self.isBlocked(id))
                            }
                        }
                        self.refresh()
                    }
                })
            }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            refresh()
        } else {
            observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            observers.removeAll()
            refreshTimer?.invalidate()
            refreshTimer = nil
            removeAllShields()
        }
    }

    private func shouldBlock(_ app: NSRunningApplication) -> Bool {
        guard isBlocking, let id = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, !app.isTerminated else { return false }
        return isBlocked(id)
    }

    func refresh() {
        guard isBlocking else { return }
        let front = NSWorkspace.shared.frontmostApplication
        let ownAppIsFront = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        for id in Array(shields.keys) {
            let stillRunning = NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { !$0.isTerminated }
            if !isBlocked(id) || !stillRunning || (!ownAppIsFront && front?.bundleIdentifier != id && !keepsShieldWhenNotFrontmost(id)) {
                unshield(bundleID: id)
            } else if shields[id]?.map(\.frame) != screenFrames() {
                unshield(bundleID: id)
                shield(bundleID: id)
            }
        }
        if let front, shouldBlock(front), let id = front.bundleIdentifier {
            shield(bundleID: id)
        }
    }

    func shield(bundleID: String) {
        guard isBlocking, isBlocked(bundleID), shields[bundleID] == nil,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              shouldBlock(app) else { return }
        if shieldsOnlyWhenFrontmost && NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundleID { return }
        // Use opaque panels, never a blurred snapshot of potentially private content.
        let content = makeShieldContent(app.localizedName ?? bundleID, bundleID)
        shields[bundleID] = screenFrames().map { frame in
            let panel = AppShieldPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.backgroundColor = .windowBackgroundColor
            panel.isOpaque = true
            panel.hidesOnDeactivate = false
            panel.contentView = NSHostingView(rootView: content)
            panel.orderFrontRegardless()
            return panel
        }
        if shieldsAreKeyable { shields[bundleID]?.first?.makeKey() }
    }

    func isShielded(_ bundleID: String) -> Bool { shields[bundleID] != nil }
    func unshield(bundleID: String) {
        let panels = shields.removeValue(forKey: bundleID) ?? []
        for panel in panels { panel.orderOut(nil); panel.contentView = nil; panel.close() }
    }
    func removeAllShields() {
        for id in Array(shields.keys) { unshield(bundleID: id) }
    }
}

@MainActor
enum AppShieldManager {
    static func displayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path)
        }
        return bundleID
    }

    @discardableResult
    static func forceClose(_ app: NSRunningApplication,
                           guard isValid: @autoclosure @escaping () -> Bool = true,
                           immediate: Bool = false) -> Bool {
        guard isValid(), !app.isTerminated, app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }
        if immediate { return app.forceTerminate() }
        let requested = app.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if isValid(), !app.isTerminated { app.forceTerminate() }
        }
        return requested
    }
}

enum AppShieldMode {
    case focus(intensity: FocusIntensity, onUnblockNow: () -> Void, onSnooze: (Int) -> Void,
               onRequestUnblock: () -> Void, remainingUnblockTime: () -> TimeInterval?, onHide: () -> Void)
}

struct AppShieldView: View {
    let appName: String
    let mode: AppShieldMode
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "moon.fill").font(.system(size: 56)).foregroundStyle(.purple)
            Text("\(appName) is blocked").font(.largeTitle.bold())
            Text("Your Focus session is active.").foregroundStyle(.secondary)
            switch mode {
            case let .focus(intensity, onUnblockNow, onSnooze, onRequestUnblock, remaining, onHide):
                if intensity == .minimal {
                    Button("Allow for this session", action: onUnblockNow)
                    Button("Snooze for 5 minutes") { onSnooze(5) }
                }
                if intensity == .strict {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        if let seconds = remaining(), seconds > 0 {
                            Text("Access available in \(Int(ceil(seconds / 60))) min").monospacedDigit()
                        } else {
                            Button("Request access", action: onRequestUnblock)
                        }
                    }
                }
                Button("Hide app", action: onHide)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
