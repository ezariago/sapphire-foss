import AppKit
import LocalAuthentication

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    let id = "dev.sapphire.nonexistent-fixture"
    var passwordCalls = 0
    let manager = AppLockManager(systemAuthentication: { _, _ in true }, passwordVerification: { input in
        passwordCalls += 1
        guard input == "fixture secret" else { throw NSError(domain: "Fixture", code: 1) }
    })
    assert(!manager.isLocked)
    let disabled = await manager.authenticateAndUnlock(bundleID: id)
    assert(!disabled)
    SettingsModel.shared.settings.appLockEnabled = true
    manager.refresh()
    assert(manager.isLocked)
    assert(!manager.verifyPassword("", for: id))
    assert(passwordCalls == 0)
    assert(!manager.verifyPassword("wrong", for: id))
    assert(manager.failedAttempts.count == 1 && manager.isLocked)
    assert(manager.verifyPassword("fixture secret", for: id))
    assert(!manager.isLocked)
    manager.lockAll()
    assert(manager.isLocked)
    let success = await manager.authenticateAndUnlock(bundleID: id)
    assert(success && !manager.isLocked)
    manager.lockAll()
    let unsupported = await manager.authenticateAndUnlock(bundleID: id, method: .faceID)
    assert(!unsupported && manager.isLocked)
    for _ in 0..<3 { assert(!manager.verifyPassword("wrong", for: id)) }
    let callsBeforeCooldown = passwordCalls
    assert(!manager.verifyPassword("fixture secret", for: id))
    assert(passwordCalls == callsBeforeCooldown && manager.isLocked)
    var raceManager: AppLockManager!
    raceManager = AppLockManager(systemAuthentication: { _, _ in
        raceManager.lockAll() // Sleep/lock while system authentication is pending.
        return true
    })
    raceManager.refresh()
    let staleSuccess = await raceManager.authenticateAndUnlock(bundleID: id)
    assert(!staleSuccess && raceManager.isLocked)
    manager.clearFailedAttempts()
    assert(manager.failedAttempts.isEmpty)
    SettingsModel.shared.settings.appLockEnabled = false
    manager.refresh()
    raceManager.refresh()
    assert(!manager.isLocked && !raceManager.isLocked)
    print("Passed App Lock denial, password, system auth, relock, cooldown and stale-auth checks using isolated providers.")
    exit(0)
}
app.run()
