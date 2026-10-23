import Foundation
var filter = KeyboardBouncePolicy()
func down(_ key: Int = 0, _ time: Double, modifiers: UInt64 = 0, repeatKey: Bool = false, interval: Double = 0.045) -> Bool {
    filter.keyDown(key, modifiers: modifiers, isRepeat: repeatKey, now: time, interval: interval)
}
func up(_ key: Int = 0, _ time: Double, modifiers: UInt64 = 0) -> Bool { filter.keyUp(key, modifiers: modifiers, now: time) }
assert(down(0, 0) && up(0, 0.01))
assert(!down(0, 0.02) && !up(0, 0.025)) // Both halves of chatter are suppressed.
assert(!down(0, 0.03) && !up(0, 0.035)) // Sliding release interval handles a chatter burst.
assert(down(0, 0.1))
assert(down(0, 0.2, repeatKey: true)) // Native held-key repeat passes.
assert(!down(0, 0.21)) // Duplicate non-repeat down does not create a second character.
assert(up(0, 0.3)) // Original accepted press still receives its release.
assert(!down(0, 0.31))
assert(!down(0, 0.32, repeatKey: true)) // A rejected press cannot start native repeat.
assert(!up(0, 0.33))
assert(down(0, 0.34, modifiers: 1)) // Modifier change is a different command.
assert(up(0, 0.35, modifiers: 0)) // Key-up matches the physical key despite modifier changes.
assert(down(1, 0.351) && up(1, 0.36)) // Different physical keys are independent.
assert(down(0, 0.37, modifiers: 1, interval: 0) && up(0, 0.38)) // Explicit bypass.
filter.reset()
assert(down(0, 1, repeatKey: true) && up(0, 1.1)) // Tap installed during a held key.
filter.reset()
assert(up(0, 2)) // An unmatched key-up is passed through.
assert(!down(0, 2.01) && !up(0, 2.02))
filter.reset() // Focus/configuration/permission/lifecycle reset.
assert(down(0, 2.03) && up(0, 2.04))
assert(down(0, 1.5) && up(0, 1.51)) // Defensive monotonic-clock rollback.
assert(down(0, 1.52, interval: .nan) && up(0, 1.53))
assert(down(-1, 0) && up(-1, 0))
print("Passed keyboard chatter pairs/bursts, held repeat, duplicate downs, modifier changes, independent keys, overrides and reset checks; no input was injected.")
