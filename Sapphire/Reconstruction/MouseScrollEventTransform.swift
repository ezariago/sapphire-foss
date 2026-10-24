#if !SAPPHIRE_FULL_BUILD
import CoreGraphics

enum MouseScrollEventTransform {
    @discardableResult
    static func apply(to event: CGEvent, speed: Double, vertical: Bool, horizontal: Bool) -> Bool {
        guard event.type == .scrollWheel,
              event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0,
              event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0,
              event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0,
              event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty,
              vertical || horizontal || speed != 1 else { return false }
        let axes: [(CGEventField, CGEventField, CGEventField, Bool)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventPointDeltaAxis1, vertical),
            (.scrollWheelEventDeltaAxis2, .scrollWheelEventFixedPtDeltaAxis2, .scrollWheelEventPointDeltaAxis2, horizontal)
        ]
        var transformed: [MouseScrollPolicy.Axis] = []
        for (lines, fixed, pixels, inverted) in axes {
            let raw = MouseScrollPolicy.Axis(lines: event.getIntegerValueField(lines), fixed: event.getDoubleValueField(fixed), pixels: event.getIntegerValueField(pixels))
            guard let value = MouseScrollPolicy.transform(raw, speed: speed, inverted: inverted) else { return false }
            transformed.append(value)
        }
        // Passing the original event keeps routing, metadata and later shared-tap handlers.
        for (index, fields) in axes.enumerated() {
            event.setIntegerValueField(fields.0, value: transformed[index].lines)
            event.setDoubleValueField(fields.1, value: transformed[index].fixed)
            event.setIntegerValueField(fields.2, value: transformed[index].pixels)
        }
        return true
    }
}
#endif
