#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI

@MainActor
final class DockLayoutsManager: ObservableObject {
    static let shared = DockLayoutsManager()
    @Published private(set) var status: String?
    private init() {}
    func start() {}
    func startDockBehaviorSync() {}
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
                let incoming = try DockLayoutDocument.decode(Data(contentsOf: url))
                var presets = SettingsModel.shared.current.dockLayoutsPresets
                for var layout in incoming {
                    // Import is additive. Never silently replace an existing preset.
                    if presets.contains(where: { $0.id == layout.id }) { layout.id = UUID() }
                    presets.append(layout)
                }
                SettingsModel.shared.settings.dockLayoutsPresets = presets
                status = "Imported \(incoming.count) Dock preset(s)."
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
    var body: some View {
        Form {
            Section("Dock presets") {
                Toggle("Enable Dock presets", isOn: $settings.settings.dockLayoutsEnabled)
                Text("Save and restore pinned apps, Dock position, size, autohide and magnification. Applying restarts the Dock; the previous settings are backed up first.")
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
            Section("Saved presets") {
                ForEach($settings.settings.dockLayoutsPresets) { $layout in
                    HStack {
                        TextField("Preset name", text: $layout.name)
                        Text("\(layout.applicationPaths.count) apps").foregroundStyle(.secondary)
                        Button("Apply") { manager.apply(layout) }.disabled(!settings.settings.dockLayoutsEnabled)
                        Button("Export") { manager.export(layout) }
                        Button("Delete") { settings.settings.dockLayoutsPresets.removeAll { $0.id == layout.id } }
                    }
                }
                if settings.settings.dockLayoutsPresets.isEmpty { Text("Save your current Dock to create a preset.").foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}
#endif
