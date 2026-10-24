import CoreGraphics

let right = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x10)
let left = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
let hyper: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
assert(SuperKeyPolicy.flags(right, source: "rightCommand").contains(hyper))
assert(SuperKeyPolicy.flags(left, source: "leftCommand").contains(hyper))
assert(SuperKeyPolicy.flags(left, source: "rightCommand") == left)
assert(SuperKeyPolicy.flags(right, source: "leftCommand") == right)
assert(SuperKeyPolicy.flags([], source: "rightCommand").isEmpty)
assert(SuperKeyPolicy.flags(.maskCommand, source: "rightCommand") == .maskCommand) // No device identity: leave it alone.
assert(SuperKeyPolicy.flags(CGEventFlags(rawValue: 0x10), source: "rightCommand").rawValue == 0x10)
assert(SuperKeyPolicy.flags(right, source: "capsLock") == right)
assert(SuperKeyPolicy.flags(right, source: "invalid") == right)
let other: CGEventFlags = [.maskAlphaShift, .maskSecondaryFn, .maskNumericPad]
assert(SuperKeyPolicy.flags(right.union(other), source: "rightCommand").contains(other))
let both = right.union(left)
assert(SuperKeyPolicy.flags(both, source: "rightCommand").rawValue & 0x18 == 0x18)

for type: CGEventType in [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .otherMouseUp, .mouseMoved, .scrollWheel] {
    let event = CGEvent(source: nil)!
    event.type = type; event.flags = right
    event.setIntegerValueField(.keyboardEventKeycode, value: 54)
    event.setIntegerValueField(.eventSourceUserData, value: 9876)
    let time = event.timestamp
    let originalKey = event.getIntegerValueField(.keyboardEventKeycode)
    assert(SuperKeyPolicy.apply(to: event, source: "rightCommand"))
    assert(event.flags.contains(hyper) && event.type == type)
    assert(event.timestamp == time && event.getIntegerValueField(.eventSourceUserData) == 9876)
    assert(event.getIntegerValueField(.keyboardEventKeycode) == originalKey)
    assert(!SuperKeyPolicy.apply(to: event, source: "rightCommand")) // Idempotent.
}
let released = CGEvent(source: nil)!
released.type = .flagsChanged; released.flags = left
assert(!SuperKeyPolicy.apply(to: released, source: "rightCommand")) // Release leaves the other physical Command intact.
assert(released.flags == left)
let unrelated = CGEvent(source: nil)!
unrelated.type = .tabletPointer; unrelated.flags = right
assert(!SuperKeyPolicy.apply(to: unrelated, source: "rightCommand"))
let wheel = CGEvent(source: nil)!
wheel.type = .scrollWheel; wheel.flags = right
wheel.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 3)
assert(SuperKeyPolicy.apply(to: wheel, source: "rightCommand"))
assert(!MouseScrollEventTransform.apply(to: wheel, speed: 2, vertical: true, horizontal: true))
assert(wheel.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3) // Hyper gestures bypass wheel customization.
print("Passed side-specific Hyper flags, release/no-latch, unsupported source, metadata, idempotence and wheel coexistence fixtures; no events were posted.")
