import AppKit
import Combine
struct MouseModifierSelection { var rawValue: UInt = 1 << 18 }
enum MouseButtonAction: String { case none, copy, back, forward }
struct Settings {
    var mouseButtonRemappingEnabled = false
    var mouseMiddleButtonAction = MouseButtonAction.none
    var mouseButton4Action = MouseButtonAction.back
    var mouseButton5Action = MouseButtonAction.forward
    var mouseMiddleModifiedAction = MouseButtonAction.none
    var mouseButton4ModifiedAction = MouseButtonAction.none
    var mouseButton5ModifiedAction = MouseButtonAction.none
    var mouseModifierSelection = MouseModifierSelection()
    var mouseModifierButtonEnabled = false
    var mouseModifierButtonNumber = 3
    var mouseExcludedAppBundleIDs: [String] = []
    var systemEnhanceQuitProtectionEnabled = false
    var systemEnhanceQuitProtectionProtectClose = true
    var systemEnhanceQuitProtectionExcludedApps: [String] = []
}
@MainActor final class SettingsModel { static let shared = SettingsModel(); @Published var settings = Settings() }
@MainActor final class AppLockManager { static let shared = AppLockManager(); var isLocked = false }
enum EventTapDecision { case pass, swallow }
enum EventTapPriority { static let filter = 100 }
final class GlobalEventTap {
    struct Token {}
    static let shared = GlobalEventTap()
    var body: ((CGEventType, CGEvent) -> EventTapDecision)?
    var reset: (() -> Void)?
    var registrations = 0
    func register(name: String, mask: CGEventMask, priority: Int, reset: @escaping () -> Void, _ body: @escaping (CGEventType, CGEvent) -> EventTapDecision) -> Token {
        registrations += 1; self.body = body; self.reset = reset; return Token()
    }
    func unregister(_ token: Token) { body = nil; reset = nil }
}
@main struct NativeLifecycle {
    @MainActor static func main() {
        _ = NSApplication.shared
        let manager = MouseButtonRemapManager.shared, hook = GlobalEventTap.shared
        manager.start(); manager.start(); assert(hook.registrations == 1)
        let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
        guard case .pass = hook.body!(.otherMouseDown, event) else { fatalError("Disabled remap consumed input") }
        SettingsModel.shared.settings.mouseButtonRemappingEnabled = true
        assert(manager.status.contains("Ready"))
        // Never feed input while enabled: the native app/menu adapters are real.
        hook.reset?(); manager.stop(); assert(hook.body == nil)
        SettingsModel.shared.settings.mouseButtonRemappingEnabled = false
        assert(manager.status == "Button remapping is off.")
        manager.start(); assert(hook.registrations == 2); manager.stop()
        print("Passed real mouse manager/native AX adapter compilation and disabled/enable/configuration/reset/teardown lifecycle with fake settings and inert hooks. No real event tap, input or menu action.")
    }
}
