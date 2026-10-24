#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import Carbon.HIToolbox

@MainActor final class CircleToSearchManager: ObservableObject {
    static let shared = CircleToSearchManager()
    let session: RegionTextSearchSession
    @Published private(set) var shortcutUnavailable = false
    private var subscription: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var sleeping = false
    private var locked = false
    private init() {
        session = RegionTextSearchSession(capture: {
            guard !IsSecureEventInputEnabled(), CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else { throw CancellationError() }
            return try await RegionTextCapture.capture(language: SettingsModel.shared.current.mediaToolsOCRLanguage)
        }, open: { NSWorkspace.shared.open($0) }, allowed: Self.allowed)
        subscription = SettingsModel.shared.$settings.map(\.regionTextSearchEnabled).removeDuplicates()
            .sink { [weak self] in self?.session.configure(enabled: $0) }
        KeyboardShortcutManager.shared.registerExternalShortcutProvider(.init(shortcuts: { [weak self] settings in
            guard settings.regionTextSearchEnabled, settings.circleToSearchEnabled else { return [] }
            let expected = settings.circleToSearchShortcut
            return [.init(identifier: ShortcutIdentifier.circleToSearch, shortcut: expected, perform: { [weak self] in
                let current = SettingsModel.shared.current
                guard current.circleToSearchEnabled, current.circleToSearchShortcut == expected,
                      !current.disabledShortcutIDs.contains(ShortcutIdentifier.circleToSearch) else { return }
                self?.selectRegion()
            })]
        }, reportUnavailable: { [weak self] in self?.shortcutUnavailable = !$0.isEmpty }), named: "FOSSRegionTextSearch")
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }
                self.sleeping = name == NSWorkspace.willSleepNotification || name == NSWorkspace.sessionDidResignActiveNotification
                self.session.suspend(self.sleeping || self.locked)
            } })
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            lockObservers.append(DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }; self.locked = name == "com.apple.screenIsLocked"
                self.session.suspend(self.sleeping || self.locked)
            } })
        }
    }
    private static func allowed() -> Bool {
        guard SettingsModel.shared.current.regionTextSearchEnabled, !IsSecureEventInputEnabled(),
              let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true else { return false }
        return !(session["CGSSessionScreenIsLocked"] as? Bool ?? false)
    }
    func selectRegion() {
        guard Self.allowed(), !sleeping, !locked, !session.busy else { return }
        session.select()
        NotificationCenter.default.post(name: .sapphireOpenCircleToSearch, object: nil)
    }
    func endResultsPresentation() { session.clear() }
}
extension Notification.Name {
    static let sapphireOpenCircleToSearch = Notification.Name("sapphireOpenCircleToSearch")
}
#endif
