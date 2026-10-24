#if !SAPPHIRE_FULL_BUILD
import SwiftUI

struct MouseButtonRemapSettingsSection: View {
    @ObservedObject private var settings = SettingsModel.shared
    @ObservedObject private var manager = MouseButtonRemapManager.shared
    var body: some View {
        Section("Mouse buttons") {
            Toggle("Remap middle and side clicks", isOn: $settings.settings.mouseButtonRemappingEnabled)
            Text("Requires Accessibility. Requests an enabled app menu item with the action’s usual shortcut. This does not post keys or read the clipboard. Some apps use different shortcuts or expose no menu item, so they may not support an action. One lookup runs at a time; rapid repeated clicks can be skipped. Native behaviour is retained for Keep native and unsupported saved actions.").foregroundStyle(.secondary)
            if settings.settings.mouseButtonRemappingEnabled {
                actionPicker("Middle button (3)", action: $settings.settings.mouseMiddleButtonAction)
                actionPicker("Side button (4)", action: $settings.settings.mouseButton4Action)
                actionPicker("Side button (5)", action: $settings.settings.mouseButton5Action)
                Picker("Keyboard modifier for alternate actions", selection: Binding(get: { settings.settings.mouseModifierSelection.rawValue }, set: { settings.settings.mouseModifierSelection = .init(rawValue: $0) })) {
                    Text("None").tag(UInt(0))
                    Text("Control").tag(NSEvent.ModifierFlags.control.rawValue)
                    Text("Option").tag(NSEvent.ModifierFlags.option.rawValue)
                    Text("Command").tag(NSEvent.ModifierFlags.command.rawValue)
                    Text("Shift").tag(NSEvent.ModifierFlags.shift.rawValue)
                    if ![UInt(0), NSEvent.ModifierFlags.control.rawValue, NSEvent.ModifierFlags.option.rawValue, NSEvent.ModifierFlags.command.rawValue, NSEvent.ModifierFlags.shift.rawValue].contains(settings.settings.mouseModifierSelection.rawValue) {
                        Text("Saved modifier combination").tag(settings.settings.mouseModifierSelection.rawValue)
                    }
                }
                actionPicker("Middle + modifier", action: $settings.settings.mouseMiddleModifiedAction)
                actionPicker("Button 4 + modifier", action: $settings.settings.mouseButton4ModifiedAction)
                actionPicker("Button 5 + modifier", action: $settings.settings.mouseButton5ModifiedAction)
                Toggle("Use a mouse button as the alternate modifier", isOn: $settings.settings.mouseModifierButtonEnabled)
                if settings.settings.mouseModifierButtonEnabled {
                    Picker("Modifier mouse button", selection: $settings.settings.mouseModifierButtonNumber) {
                        Text("Middle (3)").tag(2)
                        Text("Side (4)").tag(3)
                        Text("Side (5)").tag(4)
                        if !(2...4).contains(settings.settings.mouseModifierButtonNumber) {
                            Text("Unsupported saved button").tag(settings.settings.mouseModifierButtonNumber)
                        }
                    }
                    Text("The modifier button’s own click is consumed only when another button has a supported alternate action. Hold it while clicking that other button. Its own configured action does not run in this mode.").font(.caption).foregroundStyle(.secondary)
                }
                Text(manager.status).font(.caption).foregroundStyle(.secondary)
                Text("Acts on release in the original foreground app, within two seconds and six points of the press. Mapped drags are cancelled and consumed. Left/right clicks are untouched. App exclusions apply. Old work is cancelled after focus/settings/session/tap changes. Protected ⌘W actions are skipped. System actions listed below remain unsupported.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func actionPicker(_ title: String, action: Binding<MouseButtonAction>) -> some View {
        Picker(title, selection: action) {
            Text("Keep native").tag(MouseButtonAction.none)
            ForEach(MouseRemapCommand.allCases, id: \.rawValue) { command in
                if let value = MouseButtonAction(rawValue: command.rawValue) { Text(command.label).tag(value) }
            }
            if action.wrappedValue != .none && MouseRemapCommand(rawValue: action.wrappedValue.rawValue) == nil {
                Text("Unsupported saved action (keeps native)").tag(action.wrappedValue)
            }
        }
    }
}
#endif
