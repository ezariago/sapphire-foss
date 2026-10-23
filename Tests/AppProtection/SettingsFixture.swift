import Combine
import Foundation

enum FocusIntensity { case minimal, gentle, standard, strict }
struct Settings {
    var appLockEnabled = false
    var appLockProtectedApps: Set<String> = ["dev.sapphire.nonexistent-fixture"]
    var appLockTouchIDEnabled = true
    var appLockPasswordFallbackEnabled = true
    var appLockLockOnSleep = true
    var appLockLockOnLeave = false
    var appLockAutoLockIdleEnabled = false
    var appLockAutoLockIdleMinutes = 3
    var appLockCloseAppOnAuthFailures = false
}
@MainActor final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()
    @Published var settings = Settings()
    var current: Settings { settings }
}
