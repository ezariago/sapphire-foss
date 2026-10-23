#if !SAPPHIRE_FULL_BUILD
import Foundation

struct AppLockAuthenticationConfiguration: Equatable {
    let enabled: Bool
    let protectedApps: Set<String>
    let touchID: Bool
    let password: Bool
    let lockOnLeave: Bool
    let lockOnSleep: Bool
    let idleEnabled: Bool
    let idleMinutes: Int
    init(_ settings: Settings) {
        enabled = settings.appLockEnabled
        protectedApps = settings.appLockProtectedApps
        touchID = settings.appLockTouchIDEnabled
        password = settings.appLockPasswordFallbackEnabled
        lockOnLeave = settings.appLockLockOnLeave
        lockOnSleep = settings.appLockLockOnSleep
        idleEnabled = settings.appLockAutoLockIdleEnabled
        idleMinutes = settings.appLockAutoLockIdleMinutes
    }
}

/// Record publisher events synchronously, before a main-queue refresh can coalesce
/// a disable/re-enable sequence into the same final configuration.
final class AppLockConfigurationRevision: @unchecked Sendable {
    private let lock = NSLock()
    private var configuration: AppLockAuthenticationConfiguration
    private var revision: UInt64 = 0
    init(_ configuration: AppLockAuthenticationConfiguration) { self.configuration = configuration }
    func record(_ configuration: AppLockAuthenticationConfiguration) {
        lock.withLock {
            if configuration != self.configuration {
                self.configuration = configuration
                revision &+= 1
            }
        }
    }
    var current: UInt64 { lock.withLock { revision } }
}
#endif
