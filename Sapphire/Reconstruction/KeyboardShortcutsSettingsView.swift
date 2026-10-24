#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct KeyboardShortcutsSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var recorder = GlobalShortcutRecorder.shared
    @State private var query = ""
    @State private var status: String?
    private let recordingPrefix = "FOSSShortcutCatalog:"
    private struct Entry: Identifiable {
        var id: String
        var name: String
        var shortcut: KeyboardShortcut?
        var featureEnabled = true
        var editable = true
        var clearable = true
        var update: (KeyboardShortcut?) -> Void
    }
    var body: some View {
        Form {
            Section("Shared global shortcuts") {
                Text("Configure clipboard, emoji, OCR, App Lock privacy, Dock presets, planes and existing Snap Zone bindings. Feature switches still apply. Other features keep their own shortcut controls.").foregroundStyle(.secondary)
                if !AXIsProcessTrusted() {
                    Text("Accessibility permission is required for global key delivery.").foregroundStyle(.orange)
                    Button("Allow Accessibility…") { AccessibilityPermission.request() }
                }
                Text("Dispatcher mapping is configuration evidence; it does not verify OS delivery or conflicts with other apps.").font(.caption).foregroundStyle(.secondary)
                TextField("Search shortcuts", text: $query)
                if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
                if recorder.isRecording, recorder.recordingIdentifier?.hasPrefix(recordingPrefix) == true {
                    Button("Cancel recording") { recorder.stopRecording() }
                }
            }
            Section("Bindings") {
                ForEach(entries.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.name).font(.headline)
                            Spacer()
                            Toggle("Allow shortcut", isOn: allowed(entry.id)).labelsHidden().help("Allow this shortcut when its feature is enabled")
                        }
                        HStack {
                            Text(entry.shortcut.map { KeyboardShortcutHelper.description(for: $0.modifiers) + $0.key } ?? "No shortcut")
                                .monospaced().textSelection(.enabled)
                            Spacer()
                            if entry.editable {
                                Button("Record…") { record(entry.id) }.disabled(recorder.isRecording)
                            } else { Text("Fixed binding").font(.caption).foregroundStyle(.secondary) }
                            if entry.clearable, entry.shortcut != nil { Button("Clear") { entry.update(nil) } }
                        }
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(mappingStatus(entry)).font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 5)
                }
            }
        }.formStyle(.grouped)
            .onDisappear {
                if recorder.recordingIdentifier?.hasPrefix(recordingPrefix) == true { recorder.stopRecording() }
            }
    }
    private func allowed(_ id: String) -> Binding<Bool> {
        Binding(get: { !settings.settings.disabledShortcutIDs.contains(id) }, set: { enabled in
            if enabled { settings.settings.disabledShortcutIDs.remove(id) }
            else { settings.settings.disabledShortcutIDs.insert(id) }
        })
    }
    private func mappingStatus(_ entry: Entry) -> String {
        if settings.settings.disabledShortcutIDs.contains(entry.id) { return "Shortcut disabled" }
        if !entry.featureEnabled { return "Feature is off or its saved target is unavailable" }
        guard let shortcut = entry.shortcut else { return "Record a shortcut to configure this action" }
        return KeyboardShortcutManager.shared.isShortcutMapped(identifier: entry.id, shortcut: shortcut)
            ? "Mapped in the shared dispatcher" : "Not currently mapped — check key support, recording, permission or conflicting bindings"
    }
    private func record(_ id: String) {
        recorder.startRecording(identifier: recordingPrefix + id) { key, modifiers in
            let shortcut = KeyboardShortcut(key: key, modifiers: modifiers)
            guard DockLayout.isValidShortcut(shortcut) else {
                status = "Include Command, Control or Option in a new global shortcut."
                return
            }
            guard let current = entries.first(where: { $0.id == id }), current.editable else { return }
            let code = KeyCodeTranslator.shared.keyCode(for: shortcut.key)
            guard code != nil else { status = "That key is unavailable for the current keyboard layout."; return }
            if let conflict = entries.first(where: { candidate in
                guard candidate.id != id, candidate.featureEnabled, !settings.settings.disabledShortcutIDs.contains(candidate.id), let other = candidate.shortcut else { return false }
                return KeyCodeTranslator.shared.keyCode(for: other.key) == code && other.significantModifiers == shortcut.significantModifiers
            }) {
                status = "This combination is assigned to \(conflict.name). Change or disable that binding first."
                return
            }
            current.update(shortcut)
            status = "Updated \(current.name)."
        }
    }
    private var entries: [Entry] {
        let config = settings.settings
        var list: [Entry] = [
            .init(id: ShortcutIdentifier.clipboardPicker, name: "Clipboard picker", shortcut: config.clipboardPickerShortcut,
                  featureEnabled: config.clipboardPickerEnabled, clearable: false, update: { if let value = $0 { settings.settings.clipboardPickerShortcut = value } }),
            .init(id: ShortcutIdentifier.emojiPicker, name: "Emoji & Symbols", shortcut: config.emojiPickerShortcut,
                  featureEnabled: config.emojiEnabled, clearable: false, update: { if let value = $0 { EmojiShortcutManager.shared.setShortcut(value) } }),
            .init(id: ShortcutIdentifier.ocrScreenshot, name: "OCR screen region", shortcut: config.mediaToolsOCRShortcut,
                  featureEnabled: config.mediaToolsOCRShortcutEnabled, clearable: false, update: { if let value = $0 { settings.settings.mediaToolsOCRShortcut = value } }),
            .init(id: ShortcutIdentifier.appLockPanic, name: "App Lock privacy", shortcut: KeyboardShortcut(key: "S", modifiers: [.command, .option]),
                  featureEnabled: config.appLockEnabled && config.appLockPanicKeyEnabled, editable: false, clearable: false, update: { _ in })
        ]
        for plane in config.planes {
            let id = plane.id
            list.append(.init(id: ShortcutIdentifier.plane(id), name: "Plane · \(plane.name)", shortcut: plane.shortcut, update: { value in
                guard let index = settings.settings.planes.firstIndex(where: { $0.id == id }) else { return }
                settings.settings.planes[index].shortcut = value
            }))
        }
        for mapping in config.snapZoneShortcuts {
            let id = mapping.id
            let layouts = config.customSnapLayouts + [config.defaultSnapLayout] + LayoutTemplate.allTemplates
            let layout = layouts.first { $0.id == mapping.layoutID }
            let zone = layout?.zones.firstIndex { $0.id == mapping.zoneID }
            let name = layout.map { "\($0.name) · Zone \(zone.map { String($0 + 1) } ?? "unavailable")" } ?? "Unavailable layout"
            list.append(.init(id: ShortcutIdentifier.snapZone(layoutID: mapping.layoutID, zoneID: mapping.zoneID),
                name: "Snap Zone · \(name)", shortcut: mapping.shortcut, featureEnabled: zone != nil, update: { value in
                    guard let index = settings.settings.snapZoneShortcuts.firstIndex(where: { $0.id == id }) else { return }
                    if let value { settings.settings.snapZoneShortcuts[index].shortcut = value }
                    else { settings.settings.snapZoneShortcuts.remove(at: index) }
                }))
        }
        for preset in config.dockLayoutsPresets {
            let id = preset.id
            list.append(.init(id: ShortcutIdentifier.dockLayouts(id), name: "Dock preset · \(preset.name)", shortcut: preset.shortcut,
                featureEnabled: config.dockLayoutsEnabled && (try? preset.validated()) != nil,
                update: { DockLayoutsManager.shared.setShortcut($0, for: id) }))
        }
        var seen = Set<String>()
        return list.filter { seen.insert($0.id).inserted }
    }
}
#endif
