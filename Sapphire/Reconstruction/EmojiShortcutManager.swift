#if !SAPPHIRE_FULL_BUILD
import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class EmojiShortcutManager: ObservableObject {
    static let shared = EmojiShortcutManager()
    @Published private(set) var unavailable: Set<String> = []
    @Published private(set) var status: String?
    private var subscription: AnyCancellable?
    private var generation: UInt64 = 0
    private var running = false
    private struct Configuration: Equatable {
        var enabled: Bool
        var shortcut: KeyboardShortcut
        var excluded: Set<String>
        var disabled: Set<String>
    }
    private init() {}
    func start() {
        guard !running else { return }
        running = true
        EmojiInlineSuggestionsManager.shared.start()
        subscription = SettingsModel.shared.$settings.map {
            Configuration(enabled: $0.emojiEnabled, shortcut: $0.emojiPickerShortcut,
                excluded: $0.emojiDisabledAppBundleIDs, disabled: $0.disabledShortcutIDs)
        }.removeDuplicates().sink { [weak self] _ in
            self?.generation &+= 1
            self?.registerShortcut()
        }
    }
    private func registerShortcut() {
        guard running else { return }
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { [weak self] settings in
            guard let self, self.running, settings.emojiEnabled, DockLayout.isValidShortcut(settings.emojiPickerShortcut) else { return [] }
            let expected = settings.emojiPickerShortcut
            let revision = self.generation
            return [.init(identifier: ShortcutIdentifier.emojiPicker, shortcut: expected, perform: { [weak self] in
                self?.present(expected: expected, revision: revision)
            })]
        }, reportUnavailable: { [weak self] unavailable in self?.unavailable = unavailable }), named: "FOSSEmojiPicker")
    }
    func present(expected: KeyboardShortcut? = nil, revision: UInt64? = nil) {
        let settings = SettingsModel.shared.current
        guard running, settings.emojiEnabled, revision.map({ $0 == generation }) ?? true else { return }
        if let expected {
            guard expected == settings.emojiPickerShortcut,
                  !settings.disabledShortcutIDs.contains(ShortcutIdentifier.emojiPicker) else { return }
        }
        guard !IsSecureEventInputEnabled(), let front = NSWorkspace.shared.frontmostApplication,
              front.activationPolicy == .regular, let id = front.bundleIdentifier,
              !settings.emojiDisabledAppBundleIDs.contains(id) else {
            status = "Emoji & Symbols is unavailable in this app or during secure input."
            return
        }
        // Keep the user's app in front; let macOS own search, skin tone and insertion.
        NSApp.orderFrontCharacterPalette(nil)
        status = "Requested macOS Emoji & Symbols."
    }
    func setShortcut(_ shortcut: KeyboardShortcut) {
        guard DockLayout.isValidShortcut(shortcut) else {
            status = "Include Command, Control or Option in the shortcut."
            return
        }
        SettingsModel.shared.settings.emojiPickerShortcut = shortcut
        status = nil
    }
    func stopMonitoring() {
        EmojiInlineSuggestionsManager.shared.stop()
        running = false; generation &+= 1; subscription = nil
        KeyboardShortcutManager.shared.unregisterExternalShortcutProvider(named: "FOSSEmojiPicker")
        unavailable = []
    }
}

struct EmojiSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var manager = EmojiShortcutManager.shared
    @ObservedObject private var recorder = GlobalShortcutRecorder.shared
    @ObservedObject private var inline = EmojiInlineSuggestionsManager.shared
    var body: some View {
        Form {
            Section("Emoji & Symbols") {
                Toggle("Enable Emoji & Symbols shortcut", isOn: $settings.settings.emojiEnabled)
                Text("Uses the macOS picker for search, skin tone and insertion. Requires Accessibility for the global shortcut. The system picker manages insertion; Sapphire does not read or replace your text.").foregroundStyle(.secondary)
                HStack {
                    Text(KeyboardShortcutHelper.description(for: settings.settings.emojiPickerShortcut.modifiers) + settings.settings.emojiPickerShortcut.key)
                    Button(recorder.isRecording && recorder.recordingIdentifier == ShortcutIdentifier.emojiPicker ? "Recording…" : "Record shortcut…") {
                        recorder.startRecording(identifier: ShortcutIdentifier.emojiPicker) { key, modifiers in
                            manager.setShortcut(KeyboardShortcut(key: key, modifiers: modifiers))
                        }
                    }
                    Button("Reset shortcut") { manager.setShortcut(KeyboardShortcut(key: "Space", modifiers: [.control, .command])) }
                }
                if manager.unavailable.contains(ShortcutIdentifier.emojiPicker) || settings.settings.disabledShortcutIDs.contains(ShortcutIdentifier.emojiPicker) {
                    Text("Shortcut unavailable or disabled. Choose another combination or review shortcut settings.").foregroundStyle(.orange)
                }
                Button("Open Emoji & Symbols") { manager.present() }.disabled(!settings.settings.emojiEnabled)
                if let status = manager.status { Text(status).foregroundStyle(.secondary) }
            }
            Section("Excluded apps") {
                ForEach(settings.settings.emojiDisabledAppBundleIDs.sorted(), id: \.self) { id in
                    HStack {
                        Text(AppShieldManager.displayName(for: id))
                        Spacer()
                        Button("Remove") { settings.settings.emojiDisabledAppBundleIDs.remove(id) }
                    }
                }
                Button("Add application…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]; panel.allowsMultipleSelection = true
                    guard panel.runModal() == .OK else { return }
                    for url in panel.urls {
                        if let id = Bundle(url: url)?.bundleIdentifier { settings.settings.emojiDisabledAppBundleIDs.insert(id) }
                    }
                }
            }
            Section("Inline suggestions") {
                Toggle("Suggest emoji while typing colon aliases", isOn: $settings.settings.emojiInlineSuggestionsEnabled)
                Text("A separate opt-in: type an alias such as :smi, then click a suggestion beside the caret. Uses a small local alias list and Accessibility text-range replacement. It reads at most 65 characters around the caret, never the clipboard. Requires a compatible text editor and keyboard layout; input-method composition is skipped.").foregroundStyle(.secondary)
                Text("Suggestions expire after five seconds. Keyboard navigation and automatic colon expansion are not included. The macOS picker provides the full emoji library and skin-tone controls; inline choices use base emoji.").font(.caption).foregroundStyle(.secondary)
                Text(inline.status).font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
#endif
