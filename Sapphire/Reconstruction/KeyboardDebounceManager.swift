#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import SwiftUI

private final class KeyboardDebounceState: @unchecked Sendable {
    struct Configuration: Equatable {
        let enabled: Bool
        let interval: Double
        let overrides: [String: Double]
    }
    let lock = NSLock()
    var configuration = Configuration(enabled: false, interval: 0.045, overrides: [:])
    var policy = KeyboardBouncePolicy()
}

@MainActor
final class KeyboardDebounceManager {
    static let shared = KeyboardDebounceManager()
    private let state = KeyboardDebounceState()
    private var tap: GlobalEventTap.Token?
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private init() {}
    func start() {
        guard subscription == nil else { return }
        let state = state
        subscription = SettingsModel.shared.$settings.sink { settings in
            let config = KeyboardDebounceState.Configuration(enabled: settings.keyboardDebounceEnabled,
                interval: settings.keyboardDebounceInterval, overrides: settings.keyboardDebounceKeyIntervals)
            state.lock.withLock {
                if state.configuration != config { state.configuration = config; state.policy.reset() }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                state.lock.withLock { state.policy.reset() }
            })
        }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        tap = GlobalEventTap.shared.register(name: "FOSSKeyboardDebounce", mask: mask, priority: EventTapPriority.filter,
            reset: { state.lock.withLock { state.policy.reset() } }) { type, event in
                state.lock.withLock {
                    let config = state.configuration
                    guard config.enabled else { return .pass }
                    let key = Int(event.getIntegerValueField(.keyboardEventKeycode))
                    let modifiers = event.flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).rawValue
                    let now = ProcessInfo.processInfo.systemUptime
                    let allowed: Bool
                    if type == .keyDown {
                        allowed = state.policy.keyDown(key, modifiers: modifiers,
                            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                            now: now, interval: config.overrides[String(key)] ?? config.interval)
                    } else if type == .keyUp { allowed = state.policy.keyUp(key, modifiers: modifiers, now: now) }
                    else { return .pass }
                    return allowed ? .pass : .swallow
                }
            }
    }
    func stopMonitoring() {
        if let tap { GlobalEventTap.shared.unregister(tap) }; tap = nil
        subscription = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
        state.lock.withLock { state.policy.reset() }
    }
}

struct MouseSettingsView: View {
    @ObservedObject private var settings = SettingsModel.shared
    @State private var keyCode = ""
    @State private var overrideMilliseconds = 45.0
    @State private var error: String?
    var body: some View {
        Form {
            Section("Keyboard debounce") {
                Toggle("Filter accidental repeated key presses", isOn: $settings.settings.keyboardDebounceEnabled)
                Text("For worn keyboards that produce duplicate presses shortly after a release. Requires Accessibility permission. Native held-key repeat is retained. No typed text is recorded.").foregroundStyle(.secondary)
                Slider(value: $settings.settings.keyboardDebounceInterval, in: 0.02...0.15) { Text("Debounce interval") }
                Text("\(Int(settings.settings.keyboardDebounceInterval * 1000)) milliseconds").monospacedDigit()
            }
            Section("Per-key overrides") {
                Text("Advanced: use a macOS virtual keycode. An interval of zero leaves that key unfiltered. Overrides apply only while keyboard debounce is enabled.").foregroundStyle(.secondary)
                ForEach(settings.settings.keyboardDebounceKeyIntervals.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text("Keycode \(key): \(Int((settings.settings.keyboardDebounceKeyIntervals[key] ?? 0) * 1000)) ms")
                        Spacer()
                        Button("Remove") { settings.settings.keyboardDebounceKeyIntervals.removeValue(forKey: key) }
                    }
                }
                TextField("Keycode (0–65535)", text: $keyCode)
                Slider(value: $overrideMilliseconds, in: 0...150, step: 1) { Text("Override interval") }
                Text("\(Int(overrideMilliseconds)) milliseconds").monospacedDigit()
                Button("Save override") {
                    guard let code = UInt16(keyCode.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = "Enter a valid macOS virtual keycode."; return }
                    settings.settings.keyboardDebounceKeyIntervals[String(code)] = overrideMilliseconds / 1000
                    keyCode = ""; error = nil
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            Section("Mouse features") {
                Text("Pointer controls, focus follows mouse, extra-click filtering and Super Key are still being implemented.").foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
#endif
