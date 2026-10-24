import Foundation
import CoreGraphics

typealias Axis = MouseScrollPolicy.Axis
let raw = Axis(lines: 2, fixed: 2.5, pixels: 20)
assert(MouseScrollPolicy.transform(raw, speed: 2, inverted: true) == Axis(lines: -4, fixed: -5, pixels: -40))
assert(MouseScrollPolicy.transform(raw, speed: 1, inverted: false) == raw)
assert(MouseScrollPolicy.transform(Axis(lines: 1, fixed: 1, pixels: 1), speed: 0.25, inverted: false) == Axis(lines: 1, fixed: 0.25, pixels: 1))
assert(MouseScrollPolicy.transform(Axis(lines: 0, fixed: 0, pixels: 0), speed: 2, inverted: true) == Axis(lines: 0, fixed: 0, pixels: 0))
assert(MouseScrollPolicy.transform(raw, speed: .nan, inverted: false) == nil)
assert(MouseScrollPolicy.transform(raw, speed: 0, inverted: false) == nil)
assert(MouseScrollPolicy.transform(raw, speed: -1, inverted: false) == nil)
assert(MouseScrollPolicy.transform(Axis(lines: 1, fixed: .infinity, pixels: 1), speed: 1, inverted: false) == nil)
let extreme = MouseScrollPolicy.transform(Axis(lines: .min, fixed: -32768, pixels: .max), speed: 1e300, inverted: true)!
assert(extreme.lines == Int64(Int32.max) && extreme.pixels == Int64(Int32.min))
assert(extreme.fixed < 32768 && extreme.fixed > 32767)
assert(MouseScrollPolicy.transform(raw, speed: 10, inverted: false) == MouseScrollPolicy.transform(raw, speed: 4, inverted: false))

func wheel() -> CGEvent {
    let event = CGEvent(source: nil)!
    event.type = .scrollWheel
    event.flags = []
    event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
    event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
    event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 2)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 2.5)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 20)
    event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: -1)
    event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -1.5)
    event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -10)
    event.setIntegerValueField(.eventSourceUserData, value: 12345)
    return event
}
let event = wheel()
let timestamp = event.timestamp
assert(MouseScrollEventTransform.apply(to: event, speed: 2, vertical: true, horizontal: false))
assert(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -4)
assert(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) == -5)
assert(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -40)
assert(event.getIntegerValueField(.scrollWheelEventDeltaAxis2) == -2)
assert(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2) == -3)
assert(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2) == -20)
assert(event.timestamp == timestamp && event.getIntegerValueField(.eventSourceUserData) == 12345)
for flag: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift] {
    let event = wheel(); event.flags = flag
    assert(!MouseScrollEventTransform.apply(to: event, speed: 2, vertical: true, horizontal: true))
    assert(event.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 2)
}
for field: CGEventField in [.scrollWheelEventIsContinuous, .scrollWheelEventScrollPhase, .scrollWheelEventMomentumPhase] {
    let event = wheel(); event.setIntegerValueField(field, value: 1)
    assert(!MouseScrollEventTransform.apply(to: event, speed: 2, vertical: true, horizontal: true))
    assert(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 20)
}
let invalid = wheel()
assert(!MouseScrollEventTransform.apply(to: invalid, speed: .infinity, vertical: true, horizontal: true))
assert(invalid.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 2)
let ordinary = wheel()
assert(!MouseScrollEventTransform.apply(to: ordinary, speed: 1, vertical: false, horizontal: false))
let key = wheel(); key.type = .keyDown
assert(!MouseScrollEventTransform.apply(to: key, speed: 2, vertical: true, horizontal: true))
print("Passed wheel direction/speed, all delta representations, bounds, metadata and gesture/modifier bypass fixtures; no events were posted.")
