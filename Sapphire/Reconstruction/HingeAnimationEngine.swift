#if !SAPPHIRE_FULL_BUILD
import Combine
import CoreGraphics

@MainActor
final class HingeAnimationEngine: ObservableObject {
    @Published private(set) var phase = HingeAnimationPhase.disabled
    private(set) var state = HingeAnimationState()
    private var running = false
    private var image: CGImage?
    private var imageTicket: HingeCaptureTicket?
    private var captureTask: Task<Void, Never>?
    private var pendingTicket: HingeCaptureTicket?
    private var demand = HingeSensorDemand.none
    private var refreshing = false
    private var refreshAgain = false
    private let sample: () -> HingeAnimationSample
    private let capture: (HingeDisplayTarget) async throws -> CGImage
    private let show: (CGImage, HingeDisplayTarget, HingeAnimationVisual) -> Void
    private let hide: () -> Void
    private let sensor: (HingeSensorDemand) -> Void
    init(sample: @escaping () -> HingeAnimationSample,
         capture: @escaping (HingeDisplayTarget) async throws -> CGImage,
         show: @escaping (CGImage, HingeDisplayTarget, HingeAnimationVisual) -> Void,
         hide: @escaping () -> Void, sensor: @escaping (HingeSensorDemand) -> Void) {
        self.sample = sample; self.capture = capture; self.show = show; self.hide = hide; self.sensor = sensor
    }
    func start(configuration: HingeAnimationConfiguration) { running = true; state.configure(configuration); refresh() }
    func configure(_ configuration: HingeAnimationConfiguration) { state.configure(configuration); if running { refresh() } }
    func stop() {
        running = false; state.interrupt(phase: .disabled); captureTask?.cancel(); clearImage(); setDemand(.none); publish()
    }
    func interrupt() { guard running else { return }; state.interrupt(phase: !state.configuration.enabled ? .disabled : state.configuration.isValid ? .waitingForOpen : .invalidConfiguration); captureTask?.cancel(); clearImage(); if running { refresh() } }
    func refresh() {
        guard running else { return }
        guard !refreshing else { refreshAgain = true; return }
        refreshing = true
        repeat { refreshAgain = false; refreshOne() } while refreshAgain
        refreshing = false
    }
    private func refreshOne() {
        guard state.configuration.enabled, state.configuration.isValid else { captureTask?.cancel(); clearImage(); setDemand(.none); publish(); return }
        state.update(sample())
        if imageTicket != nil && imageTicket != state.ticket { clearImage() }
        if pendingTicket != state.ticket { captureTask?.cancel() }
        setDemand(state.sensorDemand)
        if let image, let ticket = state.ticket, state.phase == .active, let visual = state.visual {
            show(image, ticket.target, visual)
        } else { hide() }
        if let ticket = state.ticket, state.phase == .capturing, image == nil, captureTask == nil {
            let capture = capture
            pendingTicket = ticket
            captureTask = Task { @MainActor [weak self] in
                let result: Result<CGImage, Error>
                do { result = .success(try await capture(ticket.target)) } catch { result = .failure(error) }
                guard let self else { return }
                // Keep the task slot occupied through validation. Native capture
                // may ignore cancellation: no second request starts until it returns.
                self.refresh()
                guard self.running, self.state.configuration.enabled else {
                    self.captureTask = nil; self.pendingTicket = nil; return
                }
                let now = self.sample().now
                switch result {
                case .success(let image):
                    let bounded = image.width > 0 && image.height > 0 && image.width <= 2048 && image.height <= 2048
                    if self.running, !Task.isCancelled, self.state.complete(ticket, now: now, success: bounded) {
                        self.image = image; self.imageTicket = ticket
                    }
                case .failure:
                    _ = self.state.complete(ticket, now: now, success: false)
                }
                self.captureTask = nil; self.pendingTicket = nil
                if self.running { self.refresh() }
            }
        }
        publish()
    }
    private func clearImage() { image = nil; imageTicket = nil; hide() }
    private func setDemand(_ next: HingeSensorDemand) { if demand != next { demand = next; sensor(next) } }
    private func publish() { if phase != state.phase { phase = state.phase } }
}
#endif
