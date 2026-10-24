#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI

@MainActor
final class DockLayoutsManager: ObservableObject {
    static let shared = DockLayoutsManager()
    @Published private(set) var status: String?
    @Published private(set) var unavailableShortcutIDs = Set<String>()
    private var subscription: AnyCancellable?
    private struct ShortcutConfiguration: Equatable {
        let enabled: Bool
        let entries: [Entry]
        struct Entry: Equatable { let id: UUID; let shortcut: KeyboardShortcut? }
        init(_ settings: Settings) {
            enabled = settings.dockLayoutsEnabled
            entries = settings.dockLayoutsPresets.map { Entry(id: $0.id, shortcut: $0.shortcut) }
        }
    }
    private init() {}
    func start() {
        guard subscription == nil else { return }
        subscription = SettingsModel.shared.$settings.map(ShortcutConfiguration.init)
            .removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.registerShortcuts() }
    }
    private func registerShortcuts() {
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { [weak self] settings in
            guard settings.dockLayoutsEnabled else { return [] }
            return settings.dockLayoutsPresets.compactMap { layout in
                guard let shortcut = layout.shortcut, (try? layout.validated()) != nil else { return nil }
                return .init(identifier: ShortcutIdentifier.dockLayouts(layout.id), shortcut: shortcut,
                             perform: { self?.applyPreset(id: layout.id, expected: shortcut) })
            }
        }, reportUnavailable: { [weak self] unavailable in self?.unavailableShortcutIDs = unavailable }), named: "FOSSDockPresets")
    }
    private func applyPreset(id: UUID, expected: KeyboardShortcut) {
        let settings = SettingsModel.shared.current
        guard let layout = DockLayout.shortcutTarget(id: id, expected: expected,
            presets: settings.dockLayoutsPresets, enabled: settings.dockLayoutsEnabled,
            isDisabled: settings.disabledShortcutIDs.contains(ShortcutIdentifier.dockLayouts(id))) else { return }
        apply(layout)
    }
    func setShortcut(_ shortcut: KeyboardShortcut?, for id: UUID) {
        guard let index = SettingsModel.shared.settings.dockLayoutsPresets.firstIndex(where: { $0.id == id }) else { return }
        if let shortcut, !DockLayout.isValidShortcut(shortcut) {
            status = "Use a shortcut with Command, Option or Control to avoid intercepting normal typing."
            return
        }
        SettingsModel.shared.settings.dockLayoutsPresets[index].shortcut = shortcut
    }
    func startDockBehaviorSync() { DockDisplayScope.shared.start() }
    func captureCurrent() {
        do {
            let layout = try DockLayoutPreferences().capture(name: "Dock \(SettingsModel.shared.current.dockLayoutsPresets.count + 1)")
            SettingsModel.shared.settings.dockLayoutsPresets.append(layout)
            status = "Saved current Dock."
        } catch { status = error.localizedDescription }
    }
    func apply(_ layout: DockLayout) {
        guard SettingsModel.shared.current.dockLayoutsEnabled else { status = "Enable Dock presets first."; return }
        do {
            let backups = SettingsPersistence.directoryURL.appendingPathComponent("DockBackups", isDirectory: true)
            try DockLayoutPreferences().apply(layout, backupDirectory: backups)
            let restart = Process()
            restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            restart.arguments = ["Dock"]
            try restart.run()
            status = "Applied \(layout.name). Previous settings are saved in DockBackups."
        } catch { status = error.localizedDescription }
    }
    func importLayoutFiles(at urls: [URL]) {
        for url in urls {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 1_048_576 else { throw DockLayoutError.invalidPreset }
                var presets = SettingsModel.shared.current.dockLayoutsPresets
                // Imported files never install global shortcuts or replace local presets.
                let incoming = try DockLayoutDocument.presetsForImport(Data(contentsOf: url), existingIDs: Set(presets.map(\.id)))
                presets.append(contentsOf: incoming)
                SettingsModel.shared.settings.dockLayoutsPresets = presets
                status = "Imported \(incoming.count) Dock preset(s). Assign shortcuts locally if needed."
            } catch { status = "\(url.lastPathComponent): \(error.localizedDescription)" }
        }
    }
    func export(_ layout: DockLayout) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(layout.name).sapphiredocklayout"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            _ = try layout.validated()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(DockLayoutDocument(presets: [layout])).write(to: url, options: .atomic)
            status = "Exported \(layout.name)."
        } catch { status = error.localizedDescription }
    }
}

struct DockLayoutsSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var manager = DockLayoutsManager.shared
    @ObservedObject private var scope = DockDisplayScope.shared
    var body: some View {
        Form {
            Section("Dock presets") {
                Toggle("Enable Dock presets", isOn: $settings.settings.dockLayoutsEnabled)
                Text("Save and restore pinned apps, Dock position, size, autohide and magnification. Applying restarts the Dock; the previous settings are backed up first. Preset shortcuts require Accessibility permission. Imported shortcuts must be assigned locally.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save current Dock") { manager.captureCurrent() }
                    Button("Import…") {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        guard panel.runModal() == .OK else { return }
                        manager.importLayoutFiles(at: panel.urls)
                    }
                }
                if let status = manager.status { Text(status).textSelection(.enabled) }
            }
            Section("Display for Sapphire Dock enhancements") {
                Toggle("Limit Dock enhancements to one display", isOn: $settings.settings.systemEnhanceDockLocked)
                if settings.settings.systemEnhanceDockLocked {
                    Picker("Display", selection: Binding(get: { settings.settings.systemEnhanceLockedDisplayID ?? "" }, set: { settings.settings.systemEnhanceLockedDisplayID = $0.isEmpty ? nil : $0 })) {
                        Text("Choose a display…").tag("")
                        if let saved = settings.settings.systemEnhanceLockedDisplayID, !saved.isEmpty,
                           !scope.selectableDisplays.contains(where: { $0.key == saved }) {
                            Text("Saved display unavailable or needs reselection").tag(saved)
                        }
                        ForEach(scope.selectableDisplays) { display in Text(display.name + " · " + display.id).tag(display.key) }
                    }
                }
                Text(scope.status).foregroundStyle(.secondary)
                Text("Limits Sapphire’s hover/click previews and custom Dock click actions. macOS still controls where the native Dock appears. A missing or ambiguous display disables these enhancements; reconnect or select a different display. The window switcher and Dock presets are independent.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh displays") { scope.refresh() }
            }
            Section("Window previews") {
                Toggle("Enable Dock window previews", isOn: $settings.settings.systemEnhanceDockPreviewsEnabled)
                Picker("Show previews", selection: $settings.settings.systemEnhancePreviewTriggerRaw) {
                    Text("Hover").tag("hover")
                    Text("Middle click").tag("middleClick")
                    Text("Option-click").tag("modifierClick")
                }
                Picker("Layout", selection: $settings.settings.systemEnhancePreviewLayoutRaw) {
                    Text("Grid").tag("grid")
                    Text("List").tag("list")
                    Text("Carousel").tag("carousel")
                }
                Toggle("Use a compact list above six windows", isOn: $settings.settings.systemEnhanceCompactPreviewEnabled)
                Toggle("Larger thumbnails", isOn: $settings.settings.systemEnhanceEnhancedPreviewsEnabled)
                Slider(value: $settings.settings.systemEnhancePreviewDelay, in: 0...1) { Text("Hover delay") }
                Text("Accessibility is needed to find windows; Screen Recording enables thumbnails. Click triggers preserve native Dock click actions. List mode shows titles and icons without screen capture.")
                    .foregroundStyle(.secondary)
            }
            Section("Saved presets") {
                ForEach($settings.settings.dockLayoutsPresets) { $layout in
                    VStack(alignment: .leading) {
                      HStack {
                        TextField("Preset name", text: $layout.name)
                        Text("\(layout.applicationPaths.count) apps").foregroundStyle(.secondary)
                        Button("Apply") { manager.apply(layout) }.disabled(!settings.settings.dockLayoutsEnabled)
                        Button("Export") { manager.export(layout) }
                        Button("Delete") { settings.settings.dockLayoutsPresets.removeAll { $0.id == layout.id } }
                      }
                      HStack {
                        Text(layout.shortcut.map { KeyboardShortcutHelper.description(for: $0.modifiers) + $0.key } ?? "No shortcut")
                            .foregroundStyle(.secondary)
                        Button("Record shortcut…") {
                            let id = layout.id
                            GlobalShortcutRecorder.shared.startRecording(identifier: ShortcutIdentifier.dockLayouts(id)) { key, modifiers in
                                manager.setShortcut(KeyboardShortcut(key: key, modifiers: modifiers), for: id)
                            }
                        }
                        if layout.shortcut != nil { Button("Clear shortcut") { manager.setShortcut(nil, for: layout.id) } }
                        if manager.unavailableShortcutIDs.contains(ShortcutIdentifier.dockLayouts(layout.id)) || settings.settings.disabledShortcutIDs.contains(ShortcutIdentifier.dockLayouts(layout.id)) {
                            Text("Shortcut unavailable or disabled").foregroundStyle(.orange)
                        }
                      }.font(.caption)
                    }
                }
                if settings.settings.dockLayoutsPresets.isEmpty { Text("Save your current Dock to create a preset.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .onAppear { scope.start() }
    }
}
#endif
