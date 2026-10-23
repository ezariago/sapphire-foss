#if !SAPPHIRE_FULL_BUILD
import Combine
import Foundation

@MainActor
final class AppLockPanicShortcut: ObservableObject {
    static let shared = AppLockPanicShortcut()
    @Published private(set) var unavailable = false
    private var subscription: AnyCancellable?
    private struct Configuration: Equatable { let enabled: Bool; let panic: Bool }
    private init() {
        subscription = SettingsModel.shared.$settings
            .map { Configuration(enabled: $0.appLockEnabled, panic: $0.appLockPanicKeyEnabled) }
            .removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.registerShortcut() }
    }
    private func registerShortcut() {
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { settings in
            guard settings.appLockEnabled, settings.appLockPanicKeyEnabled else { return [] }
            return [.init(identifier: ShortcutIdentifier.appLockPanic,
                          shortcut: KeyboardShortcut(key: "S", modifiers: [.command, .option]),
                          perform: { AppLockManager.shared.panicHideAndLock() })]
        }, reportUnavailable: { [weak self] ids in
            self?.unavailable = ids.contains(ShortcutIdentifier.appLockPanic)
        }), named: "FOSSAppLockPanic")
    }
}
#endif
