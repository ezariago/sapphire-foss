#if !SAPPHIRE_FULL_BUILD
import AppKit
import Intents
import SwiftUI

/// Public, optional notifications-silenced signal only. No Focus names, files or control actions.
@MainActor enum MenuBarSharedFocusStatus {
    static func read() -> Bool? {
        let center = INFocusStatusCenter.default
        guard center.authorizationStatus == .authorized else { return nil }
        return center.focusStatus.isFocused
    }
    static var accessDescription: String {
        switch INFocusStatusCenter.default.authorizationStatus {
        case .authorized: "Access granted. An unshared or unavailable status still cannot match."
        case .denied: "Access denied. Review Focus Status sharing and app access in System Settings."
        case .restricted: "Focus status access is restricted by macOS."
        case .notDetermined: "Focus status access has not been requested."
        @unknown default: "Focus status access is unavailable."
        }
    }
    static func requestAccess() async {
        _ = await INFocusStatusCenter.default.requestAuthorization()
        MenuBarProfileEngine.shared.refresh()
    }
}

@MainActor struct MenuBarFocusStatusAccessView: View {
    @State private var access = MenuBarSharedFocusStatus.accessDescription
    @State private var requesting = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shared Focus status").font(.subheadline.weight(.semibold))
            Text("The shared notifications-silenced signal can reveal items when active. It does not identify or activate a named Focus. Unknown or unshared status does not match.")
                .font(.caption).foregroundStyle(.secondary)
            Text(access).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Allow shared Focus status…") {
                    requesting = true
                    Task { @MainActor in
                        await MenuBarSharedFocusStatus.requestAccess()
                        access = MenuBarSharedFocusStatus.accessDescription; requesting = false
                    }
                }.disabled(requesting)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access = MenuBarSharedFocusStatus.accessDescription
        }
    }
}
#endif
