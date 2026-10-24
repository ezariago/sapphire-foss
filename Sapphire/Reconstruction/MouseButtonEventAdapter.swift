#if !SAPPHIRE_FULL_BUILD
import CoreGraphics

enum MouseButtonEventAdapter {
    static func input(type: CGEventType, event: CGEvent, secureInput: Bool, now: Double) -> MouseRemapInput? {
        let phase: MouseRemapInput.Phase
        switch type {
        case .otherMouseDown: phase = .down
        case .otherMouseUp: phase = .up
        case .otherMouseDragged: phase = .drag
        default: return nil
        }
        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        guard (2...4).contains(number) else { return nil }
        return .init(phase: phase, button: Int(number), point: event.location, flags: event.flags.rawValue,
            targetPID: event.getIntegerValueField(.eventTargetUnixProcessID),
            synthetic: event.getIntegerValueField(.eventSourceUserData) != 0, secureInput: secureInput, now: now)
    }
}
#endif
