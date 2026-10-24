#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine

extension DockScopeConfiguration {
    init(_ settings: Settings) {
        locked = settings.systemEnhanceDockLocked; selectedDisplay = settings.systemEnhanceLockedDisplayID
        previews = settings.systemEnhanceDockPreviewsEnabled; trigger = settings.systemEnhancePreviewTriggerRaw
        layout = settings.systemEnhancePreviewLayoutRaw; delay = settings.systemEnhancePreviewDelay
        enhanced = settings.systemEnhanceEnhancedPreviewsEnabled; compact = settings.systemEnhanceCompactPreviewEnabled
        otherSpaces = settings.systemEnhanceSwitcherIncludeOtherSpaces
        clicks = settings.systemEnhanceDockClicksEnabled; clickAction = settings.systemEnhanceDockClickActionRaw
        allApps = settings.systemEnhanceDockClicksAllAppsEnabled
        selectedApps = settings.systemEnhanceDockClicksSelectedApps.sorted(); excludedApps = settings.systemEnhanceDockClicksExcludedApps.sorted()
    }
}

@MainActor
final class DockDisplayScope: ObservableObject {
    static let shared = DockDisplayScope()
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var displays: [DockScopeDisplay] = []
    private(set) var state = DockDisplayScopeState()
    private var subscription: AnyCancellable?
    private var appObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var sleeping = false
    private var locked = false
    private var started = false
    private init() {}
    func start() {
        guard !started else { return }; started = true; sleeping = false; locked = false
        subscription = SettingsModel.shared.$settings.map(DockScopeConfiguration.init).removeDuplicates()
            .sink { [weak self] configuration in
                guard let self else { return }
                self.state.update(configuration: configuration, displays: self.displays)
                self.publish()
            }
        appObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }; self.sleeping = name == NSWorkspace.willSleepNotification; self.refresh()
            } }
        }
        lockObservers = ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"].map { name in
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }; self.locked = name == "com.apple.screenIsLocked"; self.refresh()
            } }
        }
        refresh()
    }
    func stop() {
        started = false; subscription = nil
        if let appObserver { NotificationCenter.default.removeObserver(appObserver) }; appObserver = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); workspaceObservers = []
        lockObservers.forEach(DistributedNotificationCenter.default().removeObserver); lockObservers = []
        state.setSuspended(true); publish()
    }
    func refresh() {
        guard started else { return }
        let screens = NSScreen.screens.compactMap { screen -> DockScopeDisplay? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return .init(id: number.stringValue, key: screen.displayIdentifier, aliases: screen.displayIdentifierCandidates,
                         name: screen.localizedName, frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
        state.update(configuration: DockScopeConfiguration(SettingsModel.shared.current), displays: screens)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let sessionUnavailable = session?[kCGSessionOnConsoleKey as String] as? Bool != true
        let sessionLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        state.setSuspended(sleeping || locked || sessionUnavailable || sessionLocked)
        if displays != state.displays { displays = state.displays }
        publish()
    }
    private func publish() { if revision != state.epoch { revision = state.epoch } }
    func ticket(at point: CGPoint) -> DockScopeTicket? { refresh(); return state.ticket(at: point) }
    func accepts(_ ticket: DockScopeTicket) -> Bool { refresh(); return state.accepts(ticket) }
    var selectableDisplays: [DockScopeDisplay] { displays.filter { display in display.isValid && displays.filter { $0.key == display.key }.count == 1 } }
    var status: String {
        guard state.configuration.locked else { return "Sapphire Dock enhancements are available across connected displays." }
        guard let display = state.selected else { return "The selected display is missing or ambiguous. Sapphire Dock enhancements are inactive until a unique display is selected." }
        return "Sapphire Dock enhancements are limited to \(display.name)."
    }
}
#endif
