#if !SAPPHIRE_FULL_BUILD
import Foundation
import CoreGraphics

struct HingeAnimationConfiguration: Equatable {
    var enabled = false
    var activationAngle = 90.0
    var intensity = 1.0
    var maximumBlur = 135.0
    var isValid: Bool {
        activationAngle.isFinite && (45...140).contains(activationAngle)
        && intensity.isFinite && (0.5...1.5).contains(intensity)
        && maximumBlur.isFinite && (0...180).contains(maximumBlur)
    }
}
struct HingeDisplayTarget: Equatable {
    let id: UInt32
    let frame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    var isValid: Bool {
        id != 0 && (1...32768).contains(pixelWidth) && (1...32768).contains(pixelHeight)
        && [frame.minX, frame.minY, frame.maxX, frame.maxY, frame.width, frame.height].allSatisfy(\.isFinite)
        && frame.width > 0 && frame.height > 0
    }
    var captureDimensions: (Int, Int) {
        let scale = min(1, 2048.0 / Double(max(pixelWidth, pixelHeight)))
        return (max(1, Int(Double(pixelWidth) * scale)), max(1, Int(Double(pixelHeight) * scale)))
    }
}
struct HingeAnimationSample {
    static func isFresh(readAt: TimeInterval?, now: TimeInterval) -> Bool {
        guard let readAt, readAt.isFinite, readAt >= 0, now.isFinite, now >= readAt else { return false }
        return now - readAt <= 0.5
    }
    var now: TimeInterval
    var angle: Double
    var available: Bool
    var reporting: Bool
    var permission: Bool
    var unlocked: Bool
    var target: HingeDisplayTarget?
}
enum HingeAnimationPhase: String {
    case disabled, invalidConfiguration, unsupported, notReporting, permissionRequired, locked, invalidReading
    case waitingForOpen, ready, capturing, active, timedOut, captureFailed
    var message: String {
        switch self {
        case .disabled: return "Hinge animation is off."
        case .invalidConfiguration: return "Hinge settings are out of range. Adjust the sliders before enabling."
        case .unsupported: return "A supported lid sensor and one built-in display are required."
        case .notReporting: return "Waiting for a valid lid sensor reading."
        case .permissionRequired: return "Allow Screen Recording in Permissions before using hinge animation."
        case .locked: return "Hinge animation is suspended while the console session is unavailable or locked."
        case .invalidReading: return "Invalid sensor or clock reading; open the lid past the activation angle to rearm."
        case .waitingForOpen: return "Open the lid at least 5° past the activation angle to arm the next gesture."
        case .ready: return "Ready for a closing gesture."
        case .capturing: return "Preparing one temporary built-in display snapshot."
        case .active: return "Showing the temporary snapshot effect (at most four seconds)."
        case .timedOut: return "Gesture time limit reached; open the lid to rearm."
        case .captureFailed: return "Snapshot unavailable or too late; open the lid to retry."
        }
    }
}
struct HingeCaptureTicket: Equatable {
    let epoch: UInt64
    let target: HingeDisplayTarget
    let started: TimeInterval
}
struct HingeAnimationVisual: Equatable { let progress: Double; let dim: Double; let blur: Double }
enum HingeSensorDemand: Equatable { case none, standby, active }

struct HingeAnimationState {
    private(set) var configuration = HingeAnimationConfiguration()
    private(set) var phase = HingeAnimationPhase.disabled
    private(set) var ticket: HingeCaptureTicket?
    private(set) var visual: HingeAnimationVisual?
    private(set) var epoch: UInt64 = 0
    private var armed = false
    private var lastClock: TimeInterval?
    private var lastTarget: HingeDisplayTarget?
    mutating func configure(_ value: HingeAnimationConfiguration) {
        guard configuration != value else { return }; configuration = value
        interrupt(phase: !value.enabled ? .disabled : value.isValid ? .waitingForOpen : .invalidConfiguration)
    }
    mutating func interrupt(phase: HingeAnimationPhase = .waitingForOpen) {
        epoch &+= 1; armed = false; ticket = nil; visual = nil; lastClock = nil; lastTarget = nil; self.phase = phase
    }
    private mutating func fail(_ phase: HingeAnimationPhase) {
        if ticket != nil || armed { epoch &+= 1 }
        ticket = nil; visual = nil; armed = false; self.phase = phase
    }
    mutating func update(_ sample: HingeAnimationSample) {
        guard configuration.enabled else { fail(.disabled); return }
        guard configuration.isValid else { fail(.invalidConfiguration); return }
        guard sample.now.isFinite, sample.now >= 0, lastClock.map({ sample.now >= $0 }) ?? true,
              sample.angle.isFinite, (0...180).contains(sample.angle) else { fail(.invalidReading); lastClock = nil; return }
        lastClock = sample.now
        guard sample.unlocked else { fail(.locked); return }
        guard sample.available, let target = sample.target, target.isValid else { fail(.unsupported); return }
        guard sample.reporting else { fail(.notReporting); return }
        guard sample.permission else { fail(.permissionRequired); return }
        if let previous = lastTarget, previous != target { fail(.waitingForOpen) }
        lastTarget = target
        if sample.angle >= configuration.activationAngle + 5 {
            if ticket != nil { epoch &+= 1 }; ticket = nil; visual = nil; armed = true; phase = .ready; return
        }
        if sample.angle >= configuration.activationAngle {
            if ticket != nil { fail(.waitingForOpen) }; visual = nil; return
        }
        guard armed else {
            if ![.captureFailed, .timedOut].contains(phase) { phase = .waitingForOpen }; return
        }
        if let ticket {
            guard sample.now - ticket.started < 4 else { fail(.timedOut); return }
            guard phase != .capturing || sample.now - ticket.started < 2 else { fail(.captureFailed); return }
        } else {
            epoch &+= 1; ticket = .init(epoch: epoch, target: target, started: sample.now); phase = .capturing
        }
        let progress = min(1, max(0, (configuration.activationAngle - sample.angle) / configuration.activationAngle * configuration.intensity))
        visual = .init(progress: progress, dim: 0.7 * progress, blur: configuration.maximumBlur * progress)
    }
    mutating func complete(_ candidate: HingeCaptureTicket, now: TimeInterval, success: Bool) -> Bool {
        guard ticket == candidate, phase == .capturing else { return false }
        guard success, now.isFinite, now >= candidate.started, lastClock.map({ now >= $0 }) ?? true, now - candidate.started < 2 else { fail(.captureFailed); return false }
        phase = .active; return true
    }
    var sensorDemand: HingeSensorDemand {
        guard configuration.enabled, configuration.isValid, ![.locked, .permissionRequired, .unsupported].contains(phase) else { return .none }
        return ticket != nil ? .active : .standby
    }
}
#endif
