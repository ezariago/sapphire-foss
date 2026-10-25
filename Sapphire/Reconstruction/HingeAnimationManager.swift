#if !SAPPHIRE_FULL_BUILD
import AppKit
import Combine
import ScreenCaptureKit
import SwiftUI

extension HingeAnimationConfiguration {
    init(_ settings: Settings) {
        enabled = settings.systemEnhanceHingeAnimationEnabled
        activationAngle = settings.systemEnhanceHingeAnimationActivationAngle
        intensity = settings.systemEnhanceHingeAnimationIntensity
        maximumBlur = settings.systemEnhanceHingeAnimationBlur
    }
}

private final class HingeEffectPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
@MainActor private final class HingeEffectModel: ObservableObject {
    @Published var image: CGImage?
    @Published var visual = HingeAnimationVisual(progress: 0, dim: 0, blur: 0)
}
private struct HingeEffectView: View {
    @ObservedObject var model: HingeEffectModel
    var body: some View {
        GeometryReader { geometry in
            if let image = model.image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .blur(radius: model.visual.blur)
                    .overlay(Color.black.opacity(model.visual.dim))
                    .clipped()
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
@MainActor private final class HingeEffectRenderer {
    private var panel: HingeEffectPanel?
    private let model = HingeEffectModel()
    func show(_ image: CGImage, target: HingeDisplayTarget, visual: HingeAnimationVisual) {
        model.visual = visual
        guard panel == nil else { return }
        model.image = image
        let panel = HingeEffectPanel(contentRect: target.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = false; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: HingeEffectView(model: model))
        self.panel = panel
        panel.orderFrontRegardless()
    }
    func hide() {
        model.image = nil
        panel?.orderOut(nil); panel?.contentView = nil; panel?.close(); panel = nil
    }
}

@MainActor
final class SystemEnhanceHingeAnimationManager: ObservableObject {
    static let shared = SystemEnhanceHingeAnimationManager()
    @Published private(set) var status = HingeAnimationPhase.disabled.message
    var needsScreenRecordingPermission: Bool { engine.phase == .permissionRequired }
    private let renderer = HingeEffectRenderer()
    private var subscriptions = Set<AnyCancellable>()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lockObservers: [NSObjectProtocol] = []
    private var displayObserver: NSObjectProtocol?
    private var timer: Timer?
    private var started = false
    private var sleeping = false
    private var locked = false
    private var lastSensorReadingAt: TimeInterval?
    private lazy var engine = HingeAnimationEngine(sample: { [weak self] in Self.sample(suspended: self?.sleeping != false || self?.locked != false, lastReadingAt: self?.lastSensorReadingAt) },
        capture: Self.capture,
        show: { [weak self] image, target, visual in self?.renderer.show(image, target: target, visual: visual) },
        hide: { [weak self] in self?.renderer.hide() }, sensor: Self.setSensorDemand)
    private init() {}
    func start() {
        guard !started else { return }; started = true; sleeping = false; locked = false; lastSensorReadingAt = nil
        engine.$phase.sink { [weak self] in self?.status = $0.message }.store(in: &subscriptions)
        LidAngleSensor.shared.$tick.dropFirst().sink { [weak self] _ in
            self?.lastSensorReadingAt = ProcessInfo.processInfo.systemUptime; self?.engine.refresh()
        }.store(in: &subscriptions)
        let initial = HingeAnimationConfiguration(SettingsModel.shared.current)
        engine.start(configuration: initial)
        SettingsModel.shared.$settings.map(HingeAnimationConfiguration.init).removeDuplicates()
            .sink { [weak self] in self?.lastSensorReadingAt = nil; self?.engine.configure($0) }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }; self.sleeping = name == NSWorkspace.willSleepNotification; self.lastSensorReadingAt = nil; self.engine.interrupt()
            } }
        }
        lockObservers = ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"].map { name in
            DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }; self.locked = name == "com.apple.screenIsLocked"; self.lastSensorReadingAt = nil; self.engine.interrupt()
            } }
        }
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.lastSensorReadingAt = nil; self?.engine.interrupt() } }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.engine.refresh() } }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    func stop() {
        started = false; lastSensorReadingAt = nil; subscriptions.removeAll(); timer?.invalidate(); timer = nil
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); workspaceObservers = []
        lockObservers.forEach(DistributedNotificationCenter.default().removeObserver); lockObservers = []
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }; displayObserver = nil
        engine.stop(); status = HingeAnimationPhase.disabled.message
    }
    private static func setSensorDemand(_ demand: HingeSensorDemand) {
        let sensor = LidAngleSensor.shared
        switch demand {
        case .none: sensor.release(.hingeAnimation); sensor.release(.hingeAnimationStandby)
        case .standby: sensor.acquire(.hingeAnimationStandby); sensor.release(.hingeAnimation)
        case .active: sensor.acquire(.hingeAnimation); sensor.release(.hingeAnimationStandby)
        }
    }
    private static func sample(suspended: Bool, lastReadingAt: TimeInterval?) -> HingeAnimationSample {
        let now = ProcessInfo.processInfo.systemUptime
        let fresh = HingeAnimationSample.isFresh(readAt: lastReadingAt, now: now)
        let sensor = LidAngleSensor.shared
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let unlocked = !suspended && session?[kCGSessionOnConsoleKey as String] as? Bool == true && !(session?["CGSSessionScreenIsLocked"] as? Bool ?? false)
        let builtIn = NSScreen.screens.filter { CGDisplayIsBuiltin($0.displayID) != 0 }
        let target: HingeDisplayTarget? = builtIn.count == 1 ? builtIn.first.map { screen in
            .init(id: screen.displayID, frame: screen.frame, pixelWidth: CGDisplayPixelsWide(screen.displayID), pixelHeight: CGDisplayPixelsHigh(screen.displayID))
        } : nil
        return .init(now: now, angle: sensor.angle,
                     available: sensor.isAvailable, reporting: sensor.isReporting && fresh,
                     permission: CGPreflightScreenCaptureAccess(), unlocked: unlocked, target: target)
    }
    private static func capture(_ target: HingeDisplayTarget) async throws -> CGImage {
        guard target.isValid, CGPreflightScreenCaptureAccess() else { throw CaptureError.unavailable }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard !Task.isCancelled, let display = content.displays.first(where: { $0.displayID == target.id }) else { throw CaptureError.unavailable }
        let configuration = SCStreamConfiguration()
        let (width, height) = target.captureDimensions
        configuration.width = width; configuration.height = height; configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: configuration)
        guard !Task.isCancelled else { throw CaptureError.unavailable }
        return image
    }
    private enum CaptureError: Error { case unavailable }
}
#endif
