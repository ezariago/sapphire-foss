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
    @MainActor static func wait(_ condition: () async -> Bool) async {
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while !(await condition()), ProcessInfo.processInfo.systemUptime < deadline {
            try! await Task.sleep(for: .milliseconds(10))
        }
        let satisfied = await condition()
        precondition(satisfied, "Fixture deadline")
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
        for kind in [MenuBarRevealConditionKind.focusActive, .focusIdentifier, .scriptSucceeds, .scriptFails, .scriptExitCode] {
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
        let decoded = try JSONDecoder().decode(MenuBarProfile.self, from: JSONEncoder().encode(profile))
        assert(profile == decoded)
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
        print("Passed profile condition/binding/unknown-data policies, persistence and production engine opt-in/disable/re-enable/deletion/stop/restart/freshness and simulated sleep/wake fixtures using injected readings. No actual Wi-Fi, power, scripts, Focus or menu-bar changes used.")
    }
}
