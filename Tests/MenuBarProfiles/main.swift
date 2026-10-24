import AppKit

actor Reader {
    var waiting: [CheckedContinuation<MenuBarProfileSnapshot, Never>] = []
    var requestedWiFi: [Bool] = []
    func read(_ needsWiFi: Bool) async -> MenuBarProfileSnapshot {
        requestedWiFi.append(needsWiFi)
        return await withCheckedContinuation { waiting.append($0) }
    }
    func finish(_ snapshot: MenuBarProfileSnapshot) {
        precondition(!waiting.isEmpty)
        waiting.removeFirst().resume(returning: snapshot)
    }
    var count: Int { waiting.count }
}
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: TimeInterval = 100
    func read() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return time }
    func set(_ value: TimeInterval) { lock.lock(); time = value; lock.unlock() }
}
@main struct Checks {
    @MainActor static func wait(_ condition: () async -> Bool, line: Int = #line) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !(await condition()), ProcessInfo.processInfo.systemUptime < deadline {
            try! await Task.sleep(for: .milliseconds(10))
        }
        let satisfied = await condition()
        precondition(satisfied, "Fixture deadline at line \(line)")
    }
    @MainActor static func main() async throws {
        let unknown = MenuBarProfileSnapshot()
        var condition = MenuBarRevealCondition(kind: .batteryBelow)
        var profile = MenuBarProfile(name: "Fixture")
        profile.revealConditions = [condition]
        func reveal(_ snapshot: MenuBarProfileSnapshot) -> Bool { MenuBarProfilePolicy.requestsReveal(profiles: [profile], snapshot: snapshot) }
        assert(!reveal(unknown))
        assert(reveal(.init(batteryPercent: 19)))
        assert(!reveal(.init(batteryPercent: 20)) && !reveal(.init(batteryPercent: -1)) && !reveal(.init(batteryPercent: 101)))
        profile.isEnabled = false; assert(!reveal(.init(batteryPercent: 19))); profile.isEnabled = true
        for field in [\MenuBarProfile.bindsToDisplays, \.bindsToSpaces, \.bindsToFocus] {
            profile[keyPath: field] = true; assert(!reveal(.init(batteryPercent: 19))); profile[keyPath: field] = false
        }
        for kind in [MenuBarRevealConditionKind.focusIdentifier, .scriptSucceeds, .scriptFails, .scriptExitCode] {
            profile.revealConditions = [condition, .init(kind: kind)]
            assert(!reveal(.init(batteryPercent: 19))) // Do not silently ignore unsupported AND/binding semantics.
        }
        condition.batteryThreshold = Int.max
        assert(!MenuBarProfilePolicy.matches(condition, snapshot: .init(batteryPercent: 19)))
        condition.batteryThreshold = Int.min
        assert(!MenuBarProfilePolicy.matches(condition, snapshot: .init(batteryPercent: 19)))
        condition = .init(kind: .batteryAbove)
        assert(MenuBarProfilePolicy.matches(condition, snapshot: .init(batteryPercent: 21)))
        assert(!MenuBarProfilePolicy.matches(condition, snapshot: .init(batteryPercent: 20)))
        assert(!MenuBarProfilePolicy.matches(.init(kind: .charging), snapshot: unknown))
        assert(!MenuBarProfilePolicy.matches(.init(kind: .charging), snapshot: .init(isCharging: false, isPluggedIn: true)))
        assert(MenuBarProfilePolicy.matches(.init(kind: .charging), snapshot: .init(isCharging: true, isPluggedIn: true)))
        assert(!MenuBarProfilePolicy.matches(.init(kind: .onBatteryPower), snapshot: unknown))
        assert(MenuBarProfilePolicy.matches(.init(kind: .onBatteryPower), snapshot: .init(isPluggedIn: false)))
        condition = .init(kind: .wifiEquals); condition.wifiNetworkName = "Fixture WiFi"
        assert(!MenuBarProfilePolicy.matches(condition, snapshot: unknown))
        assert(!MenuBarProfilePolicy.matches(condition, snapshot: .init(wifiSSID: "fixture wifi")))
        assert(MenuBarProfilePolicy.matches(condition, snapshot: .init(wifiSSID: "Fixture WiFi")))
        assert(!MenuBarProfilePolicy.matches(.init(kind: .wifiConnected), snapshot: .init(wifiSSID: "")))
        assert(MenuBarProfilePolicy.matches(.init(kind: .wifiConnected), snapshot: .init(wifiSSID: "Fixture")))
        assert(!MenuBarProfilePolicy.matches(.init(kind: .focusActive), snapshot: unknown))
        assert(!MenuBarProfilePolicy.matches(.init(kind: .focusActive), snapshot: .init(sharedFocusActive: false)))
        assert(MenuBarProfilePolicy.matches(.init(kind: .focusActive), snapshot: .init(sharedFocusActive: true)))
        let decoded = try JSONDecoder().decode(MenuBarProfile.self, from: JSONEncoder().encode(profile))
        assert(profile == decoded)
        var displayProfile = MenuBarProfile(name: "Bound fixture")
        displayProfile.revealConditions = [.init(kind: .batteryBelow)]
        displayProfile.bindsToDisplays = true
        displayProfile.displayBindings = [.init(displayIdentifier: "uuid-A", displayLabel: "Fixture monitor")]
        assert(MenuBarProfilePolicy.isSupported(displayProfile))
        assert(!MenuBarProfilePolicy.requestsReveal(profiles: [displayProfile], snapshot: .init(batteryPercent: 10)))
        assert(MenuBarProfilePolicy.requestsReveal(profiles: [displayProfile], snapshot: .init(batteryPercent: 10, menuBarDisplayIdentifiers: ["uuid-A", "legacy-A"])))
        assert(!MenuBarProfilePolicy.requestsReveal(profiles: [displayProfile], snapshot: .init(batteryPercent: 10, menuBarDisplayIdentifiers: ["uuid-B"])))
        displayProfile.displayBindings = [.init(displayIdentifier: "legacy-A")]
        assert(MenuBarProfilePolicy.displayMatches(displayProfile, identifiers: ["uuid-A", "legacy-A"]))
        displayProfile.displayBindings = []; assert(!MenuBarProfilePolicy.displayMatches(displayProfile, identifiers: ["uuid-A"]))
        displayProfile.displayBindings = [.init(displayIdentifier: "bad\0id")]; assert(!MenuBarProfilePolicy.isSupported(displayProfile))
        displayProfile.displayBindings = Array(repeating: .init(displayIdentifier: "uuid-A"), count: 65); assert(!MenuBarProfilePolicy.isSupported(displayProfile))
        displayProfile.displayScope = .allDisplays
        assert(MenuBarProfilePolicy.isSupported(displayProfile))
        assert(MenuBarProfilePolicy.displayMatches(displayProfile, identifiers: ["uuid-B"]))
        assert(!MenuBarProfilePolicy.displayMatches(displayProfile, identifiers: nil))
        assert(!MenuBarProfilePolicy.displayMatches(displayProfile, identifiers: []))
        assert(!MenuBarProfilePolicy.displayMatches(displayProfile, identifiers: ["invalid\0id"]))
        displayProfile.displayScope = .selectedDisplays
        displayProfile.displayBindings = [.init(displayIdentifier: "uuid-A")]
        let persistedDisplay = try JSONDecoder().decode(MenuBarProfile.self, from: JSONEncoder().encode(displayProfile))
        assert(persistedDisplay == displayProfile)
        let reader = Reader()
        let clock = TestClock()
        let engine = MenuBarProfileEngine(clock: { clock.read() }, snapshotProvider: { await reader.read($0) })
        let settings = SettingsModel.shared
        profile.revealConditions = [.init(kind: .batteryBelow)]
        settings.settings.menuBarProfiles = [profile]
        engine.start(); engine.start()
        await Task.yield()
        let idleCount = await reader.count
        assert(idleCount == 0 && !engine.isRevealRequested)
        settings.settings.menuBarProfilesEnabled = true
        await wait { await reader.count == 1 }
        await reader.finish(.init(batteryPercent: 10))
        await wait { engine.isRevealRequested }
        engine.refresh()
        await wait { await reader.count == 1 }
        settings.settings.menuBarProfilesEnabled = false
        settings.settings.menuBarProfilesEnabled = true
        await wait { await reader.count == 2 }
        await reader.finish(.init(batteryPercent: 10)) // stale despite rapid re-enable
        await Task.yield()
        assert(!engine.isRevealRequested)
        await reader.finish(unknown)
        await Task.yield()
        assert(!engine.isRevealRequested)
        engine.refresh()
        await wait { await reader.count == 1 }
        engine.stop()
        await reader.finish(.init(batteryPercent: 10))
        await Task.yield()
        assert(!engine.isRevealRequested)
        engine.start()
        await wait { await reader.count == 1 }
        await reader.finish(.init(batteryPercent: 10))
        await wait { engine.isRevealRequested }
        engine.refresh()
        await wait { await reader.count == 1 }
        clock.set(121)
        engine.refresh() // A hung query cannot keep an earlier reveal alive.
        assert(!engine.isRevealRequested)
        await reader.finish(.init(batteryPercent: 10)) // Late sample is rejected.
        try await Task.sleep(for: .milliseconds(20))
        assert(!engine.isRevealRequested)
        clock.set(122)
        engine.refresh()
        await wait { await reader.count == 1 }
        await reader.finish(.init(batteryPercent: 10))
        await wait { engine.isRevealRequested }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        assert(!engine.isRevealRequested)
        engine.refresh()
        let sleepingCount = await reader.count
        assert(sleepingCount == 0)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await wait { await reader.count == 1 }
        await reader.finish(.init(batteryPercent: 10))
        await wait { engine.isRevealRequested }
        clock.set(120) // Monotonic rollback/invalid injected time fails closed.
        engine.refresh()
        assert(!engine.isRevealRequested)
        await wait { await reader.count == 1 }
        await reader.finish(unknown)
        try await Task.sleep(for: .milliseconds(20))
        settings.settings.menuBarProfiles.removeAll()
        assert(!engine.isRevealRequested)
        profile.revealConditions = [.init(kind: .wifiConnected)]
        settings.settings.menuBarProfiles = [profile]
        await wait { await reader.count == 1 }
        let requestedWiFi = await reader.requestedWiFi.last
        assert(requestedWiFi == true)
        await reader.finish(.init(wifiSSID: "Fixture"))
        await wait { engine.isRevealRequested }
        engine.stop()
        let displays = Reader()
        var context: Set<String>? = ["uuid-A", "legacy-A"]
        settings.settings.menuBarProfiles = [displayProfile]
        let displayEngine = MenuBarProfileEngine(displayContextProvider: { context }, snapshotProvider: { await displays.read($0) })
        displayEngine.start()
        await wait { await displays.count == 1 }
        context = ["uuid-B"]
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: nil)
        assert(!displayEngine.isRevealRequested)
        await displays.finish(.init(batteryPercent: 10))
        try await Task.sleep(for: .milliseconds(20))
        assert(!displayEngine.isRevealRequested)
        let excludedCount = await displays.count; assert(excludedCount == 0)
        context = ["uuid-A", "legacy-A"]
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        await wait { await displays.count == 1 }
        await displays.finish(.init(batteryPercent: 10))
        await wait { displayEngine.isRevealRequested }
        context = nil
        displayEngine.refresh(); assert(!displayEngine.isRevealRequested)
        let unknownCount = await displays.count; assert(unknownCount == 0)
        context = ["uuid-A"]
        displayEngine.refresh(); await wait { await displays.count == 1 }
        // Even without a notification, a moved target invalidates a completed reading.
        context = ["uuid-B"]
        await displays.finish(.init(batteryPercent: 10))
        try await Task.sleep(for: .milliseconds(20)); assert(!displayEngine.isRevealRequested)
        displayEngine.setDisplayContextProvider { ["uuid-A"] }
        await wait { await displays.count == 1 }
        await displays.finish(.init(batteryPercent: 10)); await wait { displayEngine.isRevealRequested }
        displayEngine.stop()
        context = ["uuid-B"]
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: nil)
        let stoppedCount = await displays.count; assert(stoppedCount == 0 && !displayEngine.isRevealRequested)
        let focusReader = Reader()
        let focusClock = TestClock()
        var focus: Bool? = nil
        var focusReads = 0
        var focusProfile = MenuBarProfile(name: "Shared Focus fixture")
        focusProfile.revealConditions = [.init(kind: .focusActive)]
        settings.settings.menuBarProfiles = [focusProfile]
        let focusEngine = MenuBarProfileEngine(sharedFocusProvider: { focusReads += 1; return focus },
            clock: { focusClock.read() }, snapshotProvider: { await focusReader.read($0) })
        focusEngine.start(); await wait { await focusReader.count == 1 }
        await focusReader.finish(.init(sharedFocusActive: true)) // Provider cannot forge the separate shared signal.
        try await Task.sleep(for: .milliseconds(20)); assert(!focusEngine.isRevealRequested)
        focus = true; focusEngine.refresh(); assert(focusEngine.isRevealRequested)
        await wait { await focusReader.count == 1 }
        focus = nil; focusEngine.refresh(); assert(!focusEngine.isRevealRequested) // Revoked/unshared, even while telemetry is pending.
        await focusReader.finish(.init(sharedFocusActive: true))
        try await Task.sleep(for: .milliseconds(20)); assert(!focusEngine.isRevealRequested)
        focus = false; focusEngine.refresh(); await wait { await focusReader.count == 1 }
        await focusReader.finish(.init()); try await Task.sleep(for: .milliseconds(20)); assert(!focusEngine.isRevealRequested)
        focus = true; focusClock.set(105); focusEngine.refresh()
        await wait { await focusReader.count == 1 }
        focus = nil; focusEngine.refresh(); assert(!focusEngine.isRevealRequested)
        focus = true; focusClock.set(119)
        await focusReader.finish(.init()); await wait { focusEngine.isRevealRequested }
        focusClock.set(126); focusEngine.refresh() // Age is measured from query start (105), not its late completion (119).
        assert(!focusEngine.isRevealRequested)
        await wait { await focusReader.count == 1 }; await focusReader.finish(.init()); await wait { focusEngine.isRevealRequested }
        focusEngine.stop()
        let readsAtStop = focusReads
        settings.settings.menuBarProfiles = [displayProfile]
        focusEngine.start(); await Task.yield()
        assert(focusReads == readsAtStop) // Excluded host requires no shared-status read.
        focusEngine.stop()
        print("Passed optional shared Focus signal, false/unknown/revoked status, pending-query invalidation, separately owned provider data, source-time freshness and no reads for excluded profiles. No native Focus query or permission prompt.")
        print("Passed host-display aliases, unknown/disconnected/empty scope, malformed/imported bindings, persistence, immediate context-change invalidation, late readings and display observer teardown with injected telemetry/context.")
        print("Passed profile condition/binding/unknown-data policies, persistence and production engine opt-in/disable/re-enable/deletion/stop/restart/freshness and simulated sleep/wake fixtures using injected readings. No actual Wi-Fi, power, scripts, Focus or menu-bar changes used.")
    }
}
