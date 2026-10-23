import Foundation
import CoreGraphics
var policy = MouseClickBouncePolicy()
let origin = CGPoint(x: 100, y: 100)
func down(_ button: Int = 0, _ time: Double, point: CGPoint = origin, modifiers: UInt64 = 0, interval: Double = 0.04) -> Bool {
    policy.down(button, at: point, modifiers: modifiers, now: time, interval: interval)
}
func up(_ button: Int = 0, _ time: Double, point: CGPoint = origin, modifiers: UInt64 = 0) -> Bool {
    policy.up(button, at: point, modifiers: modifiers, now: time)
}
assert(down(0, 0) && up(0, 0.01))
assert(!down(0, 0.02) && !up(0, 0.025))
assert(!down(0, 0.03) && !up(0, 0.035))
assert(down(0, 0.1) && up(0, 0.11)) // Intentional click outside the short threshold.
assert(down(1, 0.12) && up(1, 0.13)) // Buttons are independent.
assert(down(0, 0.12, point: CGPoint(x: 120, y: 100)) && up(0, 0.13, point: CGPoint(x: 120, y: 100)))
assert(down(0, 0.14, point: CGPoint(x: 120, y: 100), modifiers: 1))
assert(up(0, 0.15, point: CGPoint(x: 120, y: 100), modifiers: 0))
policy.reset()
assert(down(0, 1) && policy.drag(0) && up(0, 1.1))
assert(down(0, 1.11) && up(0, 1.12)) // Drop followed by a click is not chatter.
assert(!down(0, 1.13) && !policy.drag(0) && !up(0, 1.14)) // No drag stream from a rejected press.
policy.reset()
assert(down(0, 2) && !down(0, 2.001) && policy.drag(0) && up(0, 2.1)) // Original down still owns the release.
assert(up(0, 3) && down(0, 3.001) && up(0, 3.01)) // Unmatched up does not invent chatter evidence.
assert(down(0, 3.02, interval: 0) && up(0, 3.03))
policy.reset()
assert(down(0, 4) && up(0, 4.01))
assert(down(0, 3.5) && up(0, 3.51)) // Rollback is not a repeat.
policy.reset() // Focus/configuration/permission/lifecycle reset.
assert(down(0, 3.52) && up(0, 3.53))
assert(down(-1, 0) && up(-1, 0))
policy.reset()
assert(down(0, 0) && up(0, 0.01))
assert(!down(0, 0.02, point: CGPoint(x: 104, y: 100)))
policy.reset()
assert(down(0, 0) && up(0, 0.01))
assert(down(0, 0.02, point: CGPoint(x: 104.1, y: 100)))
assert(up(0, 0.03, point: CGPoint(x: CGFloat.nan, y: 100)))
assert(down(0, 0.031)) // Invalid release data clears stale held state.
print("Passed mouse chatter pairs/bursts, button/position/modifier isolation, drag/drop, duplicate-down, bypass and reset fixtures; no mouse events were injected.")
