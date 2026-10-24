import AppKit
import Combine
struct Settings {
    var systemEnhanceDockLocked = false
    var systemEnhanceLockedDisplayID: String?
    var systemEnhanceDockPreviewsEnabled = false
    var systemEnhancePreviewTriggerRaw = "hover"
    var systemEnhancePreviewLayoutRaw = "grid"
    var systemEnhancePreviewDelay = 0.25
    var systemEnhanceEnhancedPreviewsEnabled = false
    var systemEnhanceCompactPreviewEnabled = false
    var systemEnhanceSwitcherIncludeOtherSpaces = false
    var systemEnhanceDockClicksEnabled = false
    var systemEnhanceDockClickActionRaw = "minimize"
    var systemEnhanceDockClicksAllAppsEnabled = true
    var systemEnhanceDockClicksSelectedApps: [String] = []
    var systemEnhanceDockClicksExcludedApps: [String] = []
}
@MainActor final class SettingsModel {
    static let shared = SettingsModel()
    @Published var settings = Settings()
    var current: Settings { settings }
}
@main struct NativeReadback {
    @MainActor static func main() {
        _ = NSApplication.shared
        let scope = DockDisplayScope.shared
        scope.start(); scope.start(); scope.refresh()
        let before = scope.revision
        SettingsModel.shared.settings.systemEnhanceDockLocked = true
        assert(scope.state.configuration.locked && scope.revision > before)
        let lockedRevision = scope.revision
        SettingsModel.shared.settings.systemEnhanceDockLocked = false
        assert(!scope.state.configuration.locked && scope.revision > lockedRevision)
        scope.refresh()
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let shouldSuspend = session?[kCGSessionOnConsoleKey as String] as? Bool != true || (session?["CGSSessionScreenIsLocked"] as? Bool ?? false)
        assert(scope.state.suspended == shouldSuspend)
        scope.stop(); assert(scope.state.suspended)
        let stopped = scope.revision
        SettingsModel.shared.settings.systemEnhanceDockLocked = true
        assert(scope.revision == stopped)
        scope.start(); scope.refresh(); assert(scope.state.configuration.locked && scope.revision > stopped)
        scope.stop()
        print("Passed production Dock scope adapter startup/refresh, synchronous fake-settings invalidation, native screen/session readback and stop/restart subscription checks. No input monitor, Dock/window action or real preference writes.")
    }
}
