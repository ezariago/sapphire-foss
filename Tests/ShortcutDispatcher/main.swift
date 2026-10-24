import AppKit

@main struct Checks {
    @MainActor static func settle(_ milliseconds: Int = 350) async {
        try! await Task.sleep(for: .milliseconds(milliseconds))
    }
    @MainActor static func main() async {
        let model = SettingsModel.shared
        let manager = KeyboardShortcutManager.shared
        let tap = GlobalEventTap.shared
        let a = KeyboardShortcut(key: "a", modifiers: .command)
        var actions: [String] = []
        var unavailable: [String: Set<String>] = [:]
        func provider(_ label: String) -> KeyboardShortcutManager.ExternalShortcutProvider {
            .init(shortcuts: { settings in
                guard settings.externalEnabled else { return [] }
                return [.init(identifier: label, shortcut: settings.externalShortcut, perform: { actions.append(label) })]
            }, reportUnavailable: { unavailable[label] = $0 })
        }
        manager.registerExternalShortcutProvider(provider("z"), named: "Zulu")
        manager.registerExternalShortcutProvider(provider("a"), named: "Alpha")
        await settle(600)
        assert(manager.isShortcutMapped(identifier: "a", shortcut: a))
        assert(unavailable["z"] == ["z"] && unavailable["a"] == [])
        assert(tap.emit(repeatKey: true) == .pass && tap.emit(synthetic: true) == .pass)
        assert(tap.emit() == .swallow)
        await settle()
        assert(actions == ["a"])
        // Disabled/re-enabled before the queued action reaches the main queue.
        _ = tap.emit()
        model.settings.externalEnabled = false
        model.settings.externalEnabled = true
        await settle(600)
        assert(actions == ["a"])
        _ = tap.emit()
        model.settings.externalShortcut = .init(key: "b", modifiers: .command)
        await settle(600)
        assert(actions == ["a"] && !manager.isShortcutMapped(identifier: "a", shortcut: a))
        model.settings.externalShortcut = a
        await settle(600)
        _ = tap.emit()
        manager.unregisterExternalShortcutProvider(named: "Alpha")
        await settle()
        assert(actions == ["a"] && manager.isShortcutMapped(identifier: "z", shortcut: a))
        _ = tap.emit()
        ShortcutRecordingObserver.change?(true)
        ShortcutRecordingObserver.change?(false)
        await settle()
        assert(actions == ["a"])
        _ = tap.emit()
        AccessibilityTrustMonitor.shared.suspend?()
        AccessibilityTrustMonitor.shared.resume?()
        await settle()
        assert(actions == ["a"])
        _ = tap.emit()
        tap.reset?()
        await settle()
        assert(actions == ["a"])
        _ = tap.emit()
        manager.registerExternalShortcutProvider(provider("replacement"), named: "Zulu")
        await settle()
        assert(actions == ["a"])
        // Restore the provider so subsequent checks retain their expected names.
        manager.registerExternalShortcutProvider(provider("z"), named: "Zulu")
        // Irrelevant settings should neither invalidate nor lose an invocation.
        _ = tap.emit()
        model.settings.unrelated.toggle()
        await settle()
        assert(actions == ["a", "z"])
        let plane = Plane(name: "Fixture", layoutID: LayoutTemplate.columns.id, shortcut: a)
        model.settings.planes = [plane]
        await settle(600)
        assert(manager.isShortcutMapped(identifier: ShortcutIdentifier.plane(plane.id), shortcut: a))
        _ = tap.emit()
        model.settings.planes.removeAll()
        await settle(600)
        assert(WindowArrangementManager.shared.activated.isEmpty)
        model.settings.planes = [plane]
        await settle(600)
        _ = tap.emit()
        model.settings.planes[0].assignments[UUID()] = "fixture.app"
        await settle(600)
        assert(WindowArrangementManager.shared.activated.isEmpty)
        _ = tap.emit()
        await settle()
        assert(WindowArrangementManager.shared.activated.count == 1)
        let zone = SnapZoneShortcut(layoutID: LayoutTemplate.columns.id, zoneID: LayoutTemplate.columns.zones[0].id, shortcut: a)
        model.settings.snapZoneShortcuts = [zone]
        await settle(600)
        _ = tap.emit()
        model.settings.snapZoneShortcuts.removeAll()
        await settle(600)
        assert(SnappingManager.snapped.isEmpty)
        model.settings.snapZoneShortcuts = [zone]
        await settle(600)
        _ = tap.emit()
        model.settings.disabledShortcutIDs.insert(ShortcutIdentifier.snapZone(layoutID: zone.layoutID, zoneID: zone.zoneID))
        model.settings.disabledShortcutIDs.removeAll()
        await settle(600)
        assert(SnappingManager.snapped.isEmpty)
        _ = tap.emit()
        PremiumGate.allowed = false
        PremiumGate.accessChanges.send()
        await settle()
        assert(SnappingManager.snapped.isEmpty)
        PremiumGate.allowed = true
        PremiumGate.accessChanges.send()
        await settle()
        _ = tap.emit()
        await settle()
        assert(SnappingManager.snapped == [zone.zoneID])
        print("Passed production shortcut dispatcher deletion/reassignment, disable/re-enable, permission/recording/provider epochs, repeat/synthetic bypass, deterministic collision and current-action delivery fixtures. No OS hooks or key posting/window actions used.")
    }
}
