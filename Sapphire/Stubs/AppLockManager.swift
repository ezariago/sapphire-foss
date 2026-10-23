#if !SAPPHIRE_FULL_BUILD
import AppKit
import SwiftUI
import Combine
import LocalAuthentication
import OpenDirectory

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()
    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var failedAttempts: [AppLockFailedAttempt] = []
    @Published private(set) var authenticationError: String?
    private let blocker = AppBlocker()
    private var unlocked: Set<String> = []
    private var failureCounts: [String: Int] = [:]
    private var retryAfter: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var idleTimer: Timer?
    private var lastActive: String?
    private var generation = 0
    private let systemAuthentication: ((LAPolicy, String) async throws -> Bool)?
    private let passwordVerification: ((String) throws -> Void)?
    private var context: LAContext?
    private var screenLockObserver: NSObjectProtocol?

    init(systemAuthentication: ((LAPolicy, String) async throws -> Bool)? = nil,
         passwordVerification: ((String) throws -> Void)? = nil) {
        self.systemAuthentication = systemAuthentication
        self.passwordVerification = passwordVerification
        blocker.shieldsAreKeyable = true
        blocker.keepsShieldWhenNotFrontmost = { [weak self] _ in self?.isAuthenticating ?? false }
        blocker.isBlocked = { [weak self] id in self?.needsAuthentication(id) ?? false }
        blocker.makeShieldContent = { [weak self] name, id in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(AppLockOverlayView(appName: name, lockManager: self,
                hasFaceID: false, hasTouchID: SettingsModel.shared.current.appLockTouchIDEnabled,
                hasPassword: self.hasPasswordFallback,
                onFaceID: {}, onTouchID: { Task { _ = await self.authenticateAndUnlock(bundleID: id) } },
                onSubmitPassword: { self.verifyPassword($0, for: id) },
                onQuit: { self.hide(id) }, quitButtonTitle: "Hide App"))
        }
        SettingsModel.shared.$settings.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.refresh()
        }.store(in: &cancellables)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if SettingsModel.shared.current.appLockLockOnSleep { self?.lockAll() }
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if SettingsModel.shared.current.appLockLockOnLeave, let previous = self.lastActive,
                   previous != app.bundleIdentifier, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self.unlocked.remove(previous)
                    self.generation += 1
                }
                if app.processIdentifier != ProcessInfo.processInfo.processIdentifier { self.lastActive = app.bundleIdentifier }
                self.refresh()
            }
        })
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                let settings = SettingsModel.shared.current
                if settings.appLockEnabled, settings.appLockAutoLockIdleEnabled,
                   CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!) >= Double(min(120, max(1, settings.appLockAutoLockIdleMinutes)) * 60) {
                    self?.lockAll()
                }
            }
        }
        screenLockObserver = DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lockAll() }
        }
        refresh()
    }

    private func needsAuthentication(_ id: String) -> Bool {
        let settings = SettingsModel.shared.current
        return settings.appLockEnabled && settings.appLockProtectedApps.contains(id)
            && id != Bundle.main.bundleIdentifier && !unlocked.contains(id)
    }

    func refresh() {
        let settings = SettingsModel.shared.current
        unlocked.formIntersection(settings.appLockProtectedApps)
        if !settings.appLockEnabled { unlocked.removeAll() }
        blocker.setBlocking(settings.appLockEnabled)
        isLocked = settings.appLockEnabled && !settings.appLockProtectedApps.subtracting(unlocked).isEmpty
    }

    func lockAll() {
        generation += 1
        context?.invalidate()
        unlocked.removeAll()
        refresh()
    }

    private func hide(_ id: String) {
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.hide() }
        blocker.unshield(bundleID: id)
    }

    func authenticateAndUnlock() async -> Bool {
        guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return await authenticateAndUnlock(bundleID: id)
    }
    func authenticateAndUnlock(bundleID: String, method: AppLockAuthMethod = .auto) async -> Bool {
        let stamp = generation
        guard needsAuthentication(bundleID), await authenticate(bundleID: bundleID, method: method),
              stamp == generation, needsAuthentication(bundleID) else { return false }
        unlock(bundleID)
        return true
    }
    func authenticateSettingsAccess(method: AppLockAuthMethod = .auto) async -> Bool {
        await authenticate(bundleID: Bundle.main.bundleIdentifier ?? "Sapphire", method: method)
    }

    private func authenticate(bundleID: String, method: AppLockAuthMethod) async -> Bool {
        guard !isAuthenticating, canRetry(bundleID) else { return false }
        let settings = SettingsModel.shared.current
        let settingsAccess = bundleID == (Bundle.main.bundleIdentifier ?? "Sapphire")
        guard method != .faceID else {
            authenticationError = "Camera authentication is not available for App Lock. Use Touch ID or your Mac login password."
            return false
        }
        guard settingsAccess || settings.appLockTouchIDEnabled || settings.appLockPasswordFallbackEnabled else {
            authenticationError = "Enable Touch ID or Mac login password authentication."
            return false
        }
        isAuthenticating = true
        authenticationError = nil
        let auth = LAContext()
        context = auth
        let stamp = generation
        defer { isAuthenticating = false; context = nil }
        // A password-only configuration must not silently allow biometrics.
        if !settingsAccess && !settings.appLockTouchIDEnabled {
            authenticationError = "Enter your Mac login password in the shield."
            return false
        }
        let policy: LAPolicy = !settingsAccess && (method == .touchID || !settings.appLockPasswordFallbackEnabled)
            ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        do {
            let reason = "Unlock \(AppShieldManager.displayName(for: bundleID))"
            let success: Bool
            if let systemAuthentication {
                success = try await systemAuthentication(policy, reason)
            } else {
                success = try await auth.evaluatePolicy(policy, localizedReason: reason)
            }
            return success && stamp == generation
        } catch {
            authenticationError = error.localizedDescription
            if (error as? LAError)?.code == .authenticationFailed { recordFailure(bundleID, method: "Touch ID") }
            return false
        }
    }

    func verifyPassword(_ password: String, for bundleID: String) -> Bool {
        guard !password.isEmpty, hasPasswordFallback, !isAuthenticating, needsAuthentication(bundleID), canRetry(bundleID) else { return false }
        // OpenDirectory receives the password in process; it is never put in a
        // process argument, preferences, a log, or the pairing Keychain.
        do {
            if let passwordVerification {
                try passwordVerification(password)
            } else {
                let node = try ODNode(session: ODSession.default(), type: UInt32(kODNodeTypeAuthentication))
                let user = try node.record(withRecordType: kODRecordTypeUsers, name: NSUserName(), attributes: nil)
                try user.verifyPassword(password)
            }
            unlock(bundleID)
            return true
        } catch {
            recordFailure(bundleID, method: "Mac login password")
            authenticationError = "The Mac login password was not accepted."
            return false
        }
    }

    private func unlock(_ id: String) {
        unlocked.insert(id)
        failureCounts[id] = nil
        retryAfter[id] = nil
        authenticationError = nil
        blocker.unshield(bundleID: id)
        refresh()
    }
    private func canRetry(_ id: String) -> Bool {
        if let until = retryAfter[id], until > Date() {
            authenticationError = "Wait \(Int(ceil(until.timeIntervalSinceNow))) seconds before trying again."
            return false
        }
        return true
    }
    private func recordFailure(_ id: String, method: String) {
        failureCounts[id, default: 0] += 1
        failedAttempts.insert(AppLockFailedAttempt(id: UUID(), bundleID: id, appName: AppShieldManager.displayName(for: id), timestamp: .now, method: method), at: 0)
        failedAttempts = Array(failedAttempts.prefix(100))
        if failureCounts[id, default: 0] >= 3 {
            retryAfter[id] = Date().addingTimeInterval(30)
            if SettingsModel.shared.current.appLockCloseAppOnAuthFailures { hide(id) }
        }
    }
    func clearFailedAttempts() { failedAttempts.removeAll() }
    var hasPasswordFallback: Bool { SettingsModel.shared.current.appLockPasswordFallbackEnabled }
}

enum AppLockAuthMethod { case auto, faceID, touchID }
struct AppLockFailedAttempt: Codable, Identifiable {
    let id: UUID
    let bundleID: String
    let appName: String
    let timestamp: Date
    let method: String
}
#endif
