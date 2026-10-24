#if !SAPPHIRE_FULL_BUILD
import CoreGraphics

enum SuperKeyPolicy {
    /// Device-side Command masks from the SDK's IOLLEvent.h. Caps Lock is latching
    /// and intentionally unsupported by this event-flags-only implementation.
    static func flags(_ flags: CGEventFlags, source: String) -> CGEventFlags {
        let device: UInt64
        switch source {
        case "leftCommand": device = 0x00000008
        case "rightCommand": device = 0x00000010
        default: return flags
        }
        guard flags.rawValue & device != 0, flags.contains(.maskCommand) else { return flags }
        return flags.union([.maskCommand, .maskControl, .maskAlternate, .maskShift])
    }
    static func apply(to event: CGEvent, source: String) -> Bool {
        switch event.type {
        case .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
             .otherMouseDragged, .mouseMoved, .scrollWheel: break
        default: return false
        }
        let result = flags(event.flags, source: source)
        guard result != event.flags else { return false }
        event.flags = result
        return true
    }
}
#endif
