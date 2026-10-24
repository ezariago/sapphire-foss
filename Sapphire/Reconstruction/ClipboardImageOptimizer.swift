#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import Carbon.HIToolbox

@MainActor
final class ClipboardImageOptimizer {
    static let shared = ClipboardImageOptimizer()
    private let state = ClipboardImageOptimizationState()
    private let encoder = ClipboardImageEncoder()
    private var subscription: AnyCancellable?
    private var monitor: PasteboardChangeMonitor.Token?
    private var task: Task<Void, Never>?
    private var observedCount: Int?
    private var observers: [NSObjectProtocol] = []
    private var lockObserver: NSObjectProtocol?
    private init() {}
    func start() {
        guard subscription == nil else { return }
        subscription = SettingsModel.shared.$settings
            .map { ClipboardImageOptimizationConfiguration(enabled: $0.mediaToolsAutoOptimizeClipboard, maxDimension: $0.mediaToolsMaxImageDimension, excludedApps: Set($0.clipboardIgnoredAppBundleIDs)) }
            .removeDuplicates()
            .sink { [weak self] configuration in
                guard let self else { return }
                self.state.configure(configuration)
                self.task?.cancel(); self.task = nil
                if configuration.enabled, self.monitor == nil {
                    // Enabling does not modify an image already on the clipboard.
                    self.observedCount = NSPasteboard.general.changeCount
                    self.monitor = PasteboardChangeMonitor.shared.subscribe(interval: 0.2, priority: -5) { [weak self] in self?.observe($0) }
                } else if !configuration.enabled, let monitor = self.monitor {
                    PasteboardChangeMonitor.shared.unsubscribe(monitor); self.monitor = nil
                }
            }
        let center = NSWorkspace.shared.notificationCenter
        observers = [NSWorkspace.didActivateApplicationNotification, NSWorkspace.willSleepNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancelPending() }
            }
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelPending() }
        }
    }
    private func cancelPending() {
        state.invalidate()
        task?.cancel(); task = nil
    }
    private func observe(_ count: Int) {
        guard count != observedCount else { return }
        observedCount = count
        task?.cancel(); task = nil
        // Invalidate even if this revision turns out to be text or rich content.
        state.invalidate()
        let (configuration, ticket) = state.ticket()
        guard configuration.enabled, !IsSecureEventInputEnabled(),
              let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier, !configuration.excludedApps.contains(bundleID) else { return }
        let sourcePID = app.processIdentifier
        let state = state
        PasteboardLane.shared.run({ pasteboard in
            guard state.accepts(ticket) else { return nil as ClipboardImageOptimizationInput? }
            return ClipboardImageOptimizationTransaction.capture(pasteboard, expectedCount: count)
        }, completion: { [weak self] input in
            guard let self, let input, state.accepts(ticket) else { return }
            let encoder = self.encoder
            self.task = Task { [weak self] in
                guard let png = await encoder.optimize(input.data, maxDimension: configuration.maxDimension),
                      !Task.isCancelled, state.accepts(ticket), self != nil,
                      !IsSecureEventInputEnabled(),
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == sourcePID else { return }
                PasteboardLane.shared.write({ pasteboard in
                    ClipboardImageOptimizationTransaction.commit(png, input: input, to: pasteboard, isCurrent: { state.accepts(ticket) })
                })
            }
        })
    }
    func stop() {
        cancelPending()
        state.configure(.init(enabled: false, maxDimension: 2048))
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers.removeAll()
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver) }; lockObserver = nil
        if let monitor { PasteboardChangeMonitor.shared.unsubscribe(monitor) }; monitor = nil
        subscription = nil
        observedCount = nil
    }
}
#endif
