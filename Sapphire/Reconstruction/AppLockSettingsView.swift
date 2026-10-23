#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppLockSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var manager = AppLockManager.shared
    @ObservedObject private var panicShortcut = AppLockPanicShortcut.shared
    @State private var authorized = false
    @State private var message: String?
    var body: some View {
        Form {
            Section("App Lock") {
                Text("Require authentication when protected apps become active. This is a privacy shield within your logged-in session; use the macOS lock screen to secure an unattended Mac.")
                if settings.settings.appLockEnabled && !authorized {
                    Button("Authenticate to change App Lock") {
                        Task {
                            authorized = await manager.authenticateSettingsAccess()
                            if !authorized { message = manager.authenticationError }
                        }
                    }
                }
                Toggle("Enable App Lock", isOn: $settings.settings.appLockEnabled)
                    .disabled(settings.settings.appLockEnabled && !authorized)
                if let message { Text(message).foregroundStyle(.red) }
            }
            Section("Authentication") {
                Toggle("Touch ID / system authentication", isOn: $settings.settings.appLockTouchIDEnabled)
                Toggle("Mac login password", isOn: $settings.settings.appLockPasswordFallbackEnabled)
                Text("Passwords are checked by macOS and are never stored by App Lock. Camera Face ID is not used by this implementation.")
                    .foregroundStyle(.secondary)
            }
            .disabled(settings.settings.appLockEnabled && !authorized)
            Section("Protected apps") {
                ForEach(settings.settings.appLockProtectedApps.sorted(), id: \.self) { id in
                    HStack {
                        Text(AppShieldManager.displayName(for: id))
                        Spacer()
                        Button("Remove") { settings.settings.appLockProtectedApps.remove(id) }
                    }
                }
                Button("Add application…", action: chooseApp)
            }
            .disabled(settings.settings.appLockEnabled && !authorized)
            Section("Relocking") {
                Toggle("Lock when leaving a protected app", isOn: $settings.settings.appLockLockOnLeave)
                Toggle("Lock on sleep", isOn: $settings.settings.appLockLockOnSleep)
                Toggle("Lock after inactivity", isOn: $settings.settings.appLockAutoLockIdleEnabled)
                Stepper("Idle timeout: \(settings.settings.appLockAutoLockIdleMinutes) min", value: $settings.settings.appLockAutoLockIdleMinutes, in: 1...120)
                Button("Lock protected apps now") { manager.lockAll() }
            }
            .disabled(settings.settings.appLockEnabled && !authorized)
            Section("Privacy shortcut") {
                Toggle("Enable ⌘⌥S to hide and lock protected apps", isOn: $settings.settings.appLockPanicKeyEnabled)
                    .disabled(settings.settings.appLockEnabled && !authorized)
                Text("Requires Accessibility permission. Relocks first and asks macOS to hide protected apps without quitting them. Shields remain if hiding fails; returning to an app requires authentication.")
                    .foregroundStyle(.secondary)
                if panicShortcut.unavailable || settings.settings.disabledShortcutIDs.contains(ShortcutIdentifier.appLockPanic) {
                    Text("The privacy shortcut is unavailable or disabled. Resolve the shortcut conflict or use the button below.").foregroundStyle(.orange)
                }
                Button("Hide and lock protected apps now") { manager.panicHideAndLock() }
                    .disabled(!settings.settings.appLockEnabled || !settings.settings.appLockPanicKeyEnabled)
            }
            Section("Recent failed authentication") {
                ForEach(manager.failedAttempts.prefix(20)) { attempt in
                    HStack {
                        Text(attempt.appName)
                        Spacer()
                        Text(attempt.timestamp, style: .time).foregroundStyle(.secondary)
                        Text(attempt.method).foregroundStyle(.secondary)
                    }
                }
                if manager.failedAttempts.isEmpty { Text("No failed attempts this session.").foregroundStyle(.secondary) }
                Button("Clear log") { manager.clearFailedAttempts() }
                    .disabled(settings.settings.appLockEnabled && !authorized)
            }
        }
        .formStyle(.grouped)
        .onDisappear { authorized = false }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in authorized = false }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.willSleepNotification)) { _ in authorized = false }
        .onChange(of: settings.settings.appLockTouchIDEnabled) { _, value in
            if !value && !settings.settings.appLockPasswordFallbackEnabled { settings.settings.appLockPasswordFallbackEnabled = true }
        }
        .onChange(of: settings.settings.appLockPasswordFallbackEnabled) { _, value in
            if !value && !settings.settings.appLockTouchIDEnabled { settings.settings.appLockTouchIDEnabled = true }
        }
    }
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier,
                  !["com.apple.finder", "com.apple.systempreferences", "com.apple.SystemSettings", "com.apple.dock"].contains(id) else { continue }
            settings.settings.appLockProtectedApps.insert(id)
        }
    }
}
#endif
