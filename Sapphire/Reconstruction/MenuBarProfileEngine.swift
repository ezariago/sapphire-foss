#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import CoreWLAN
import IOKit.ps

@MainActor
final class MenuBarProfileEngine {
    struct FocusModeOption: Identifiable, Sendable {
        let identifier: String
        let name: String
        let symbolName: String
        var id: String { identifier }
    }
    typealias SnapshotProvider = @Sendable (Bool) async -> MenuBarProfileSnapshot
    static let shared = MenuBarProfileEngine()
    private(set) var isRevealRequested = false
    private var started = false
    private var sleeping = false
    private var generation: UInt64 = 0
    private var configuration = Configuration()
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private let snapshotProvider: SnapshotProvider
    private let clock: @Sendable () -> TimeInterval
    private var lastReadingAt: TimeInterval?
    private var displayContextProvider: () -> Set<String>?
    private var displayContext: Set<String>?
    private var displayObservers: [NSObjectProtocol] = []
    private struct Configuration: Equatable {
        var enabled = false
        var profiles: [MenuBarProfile] = []
    }

    init(displayContextProvider: @escaping () -> Set<String>? = { nil }, clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         snapshotProvider: @escaping SnapshotProvider = { needsWiFi in
        await Task.detached(priority: .utility) { readSnapshot(needsWiFi: needsWiFi) }.value
    }) { self.snapshotProvider = snapshotProvider; self.clock = clock; self.displayContextProvider = displayContextProvider }

    func setDisplayContextProvider(_ provider: @escaping () -> Set<String>?) {
        displayContextProvider = provider
        invalidate(); displayContext = nil
        if started { refresh() }
    }

    func start() {
        guard !started else { return }
        started = true
        subscription = SettingsModel.shared.$settings
            .map { Configuration(enabled: $0.menuBarProfilesEnabled, profiles: $0.menuBarProfiles) }
            .removeDuplicates()
            .sink { [weak self] value in self?.configure(value) }
        displayObservers = [NSApplication.didChangeScreenParametersNotification, NSWindow.didChangeScreenNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.displayContextProvider() != self.displayContext else { return }
                    self.refresh()
                }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleeping = true
                    self?.invalidate()
                    self?.timer?.invalidate(); self?.timer = nil
                }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sleeping = false; self?.restartPolling() }
            }
        ]
    }
    func stop() {
        started = false
        sleeping = false
        subscription = nil
        timer?.invalidate(); timer = nil
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
        displayObservers.forEach(NotificationCenter.default.removeObserver); displayObservers.removeAll()
        displayContext = nil
        invalidate()
    }
    private func configure(_ value: Configuration) {
        guard started else { return }
        configuration = value
        invalidate()
        restartPolling()
    }
    private func restartPolling() {
        timer?.invalidate(); timer = nil
        guard started, !sleeping, configuration.enabled else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    private func invalidate() {
        generation &+= 1
        lastReadingAt = nil
        refreshTask?.cancel(); refreshTask = nil
        setReveal(false)
    }
    func refresh() {
        guard started, !sleeping, configuration.enabled else { return }
        let currentDisplay = displayContextProvider()
        if currentDisplay != displayContext { invalidate(); displayContext = currentDisplay }
        let now = clock()
        if let previous = lastReadingAt, !Self.isFresh(previous, at: now) { setReveal(false) }
        guard refreshTask == nil else { return }
        let profiles = configuration.profiles.filter { $0.isEnabled && !$0.revealConditions.isEmpty && MenuBarProfilePolicy.isSupported($0)
            && MenuBarProfilePolicy.displayMatches($0, identifiers: currentDisplay) }
        guard !profiles.isEmpty else { setReveal(false); return }
        let ticket = generation
        let needsWiFi = profiles.contains { $0.revealConditions.contains { [.wifiEquals, .wifiConnected].contains($0.kind) } }
        let provider = snapshotProvider
        refreshTask = Task { [weak self] in
            var snapshot = await provider(needsWiFi)
            guard !Task.isCancelled, let self, self.started, !self.sleeping,
                  self.configuration.enabled, self.generation == ticket else { return }
            self.refreshTask = nil
            guard self.displayContextProvider() == currentDisplay else {
                self.invalidate(); self.refresh(); return
            }
            snapshot.menuBarDisplayIdentifiers = currentDisplay
            let completedAt = self.clock()
            self.lastReadingAt = completedAt
            self.setReveal(Self.isFresh(now, at: completedAt)
                && MenuBarProfilePolicy.requestsReveal(profiles: profiles, snapshot: snapshot))
        }
    }
    private nonisolated static func isFresh(_ sampledAt: TimeInterval, at now: TimeInterval) -> Bool {
        sampledAt.isFinite && now.isFinite && now >= sampledAt && now - sampledAt <= 20
    }
    private func setReveal(_ value: Bool) {
        guard value != isRevealRequested else { return }
        isRevealRequested = value
        NotificationCenter.default.post(name: .menuBarProfilesDidChange, object: self)
    }
    nonisolated static func fetchAvailableFocusModes() -> [FocusModeOption] { [] }

    /// Read state only: never scan/associate Wi-Fi, request permission or run scripts.
    nonisolated private static func readSnapshot(needsWiFi: Bool) -> MenuBarProfileSnapshot {
        var result = MenuBarProfileSnapshot()
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
           let source = sources.first,
           let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] {
            if let current = values[kIOPSCurrentCapacityKey] as? Int,
               let maximum = values[kIOPSMaxCapacityKey] as? Int,
               maximum > 0, current >= 0, current <= maximum {
                result.batteryPercent = Int((Double(current) / Double(maximum) * 100).rounded())
            }
            switch values[kIOPSPowerSourceStateKey] as? String {
            case kIOPSACPowerValue: result.isPluggedIn = true
            case kIOPSBatteryPowerValue: result.isPluggedIn = false
            default: break
            }
            result.isCharging = values[kIOPSIsChargingKey] as? Bool
        }
        if needsWiFi, let wifi = CWWiFiClient.shared().interface(), wifi.powerOn() {
            result.wifiSSID = wifi.ssid()
        }
        return result
    }
}
#endif
