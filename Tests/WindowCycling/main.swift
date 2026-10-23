import Foundation
import CoreGraphics

var ring = WindowCyclePolicy()
assert(ring.next(windows: ["a", "b", "c"], focused: "a") == "b")
// AX commonly reorders the focused window to the beginning after activation.
assert(ring.next(windows: ["b", "a", "c"], focused: "b") == "c")
assert(ring.next(windows: ["c", "b", "a"], focused: "c") == "a")
assert(ring.next(windows: ["c", "b"], focused: "c") == "b") // Closed window removed.
assert(ring.next(windows: ["b", "d", "c"], focused: "b") == "c") // New window joins ring.
assert(ring.next(windows: ["c", "d", "b"], focused: nil) == "d") // No focused AX attribute.
assert(ring.next(windows: ["d", "d"], focused: "d") == "d")
assert(ring.next(windows: [], focused: nil) == nil)
assert(ring.next(windows: ["replacement"], focused: "closed") == "replacement")
var anotherApp = WindowCyclePolicy()
assert(anotherApp.next(windows: ["x", "y"], focused: "x") == "y")
assert(ring.next(windows: ["replacement", "second"], focused: "replacement") == "second")

let a = CGRect(x: 0, y: 20, width: 800, height: 600)
let b = CGRect(x: 900, y: 20, width: 800, height: 600)
let candidates = [WindowPreviewCandidate(id: 1, title: "Untitled", bounds: a),
                  WindowPreviewCandidate(id: 2, title: "Untitled", bounds: b)]
assert(WindowPreviewMatcher.match(title: "Untitled", bounds: b, candidates: candidates) == 2)
assert(WindowPreviewMatcher.match(title: "Untitled", bounds: nil, candidates: candidates) == nil)
assert(WindowPreviewMatcher.match(title: "Other document", bounds: b, candidates: candidates) == nil)
assert(WindowPreviewMatcher.match(title: "Untitled", bounds: a.offsetBy(dx: 1, dy: -1), candidates: candidates) == 1)
assert(WindowPreviewMatcher.match(title: "Untitled", bounds: a.offsetBy(dx: 50, dy: 0), candidates: candidates) == nil)
let noTitles = candidates.map { WindowPreviewCandidate(id: $0.id, title: nil, bounds: $0.bounds) }
assert(WindowPreviewMatcher.match(title: "Private title", bounds: b, candidates: noTitles) == 2)
let duplicate = [candidates[0], WindowPreviewCandidate(id: 3, title: "Untitled", bounds: a)]
assert(WindowPreviewMatcher.match(title: "Untitled", bounds: a, candidates: duplicate) == nil)
assert(WindowPreviewMatcher.match(title: "Untitled", bounds: a, candidates: []) == nil)
var keys = WindowSwitcherKeyPolicy()
func down(_ code: Int, command: Bool = true, option: Bool = false, control: Bool = false, shift: Bool = false) -> WindowSwitcherKeyPolicy.Action? {
    keys.keyDown(code, command: command, option: option, control: control, shift: shift)
}
assert(down(48) == nil)
assert(keys.configure(enabled: true, activation: "both", columns: 3))
let startingEpoch = keys.epoch
assert(!keys.configure(enabled: true, activation: "both", columns: 3))
assert(keys.epoch == startingEpoch)
assert(down(48, control: true) == nil)
assert(down(48) == .advance(reverse: false) && keys.active)
assert(keys.keyUp(48) == .suppress)
assert(down(123) == .move(-1) && down(124) == .move(1))
assert(down(125) == .move(3) && down(126) == .move(-3))
assert(down(48, shift: true) == .advance(reverse: true))
assert(keys.flagsChanged(command: true, option: false) == nil)
assert(keys.flagsChanged(command: false, option: false) == .commit && !keys.active)
assert(down(48) == .suppress) // Held/repeating Tab cannot leak into the chosen app.
assert(keys.keyUp(48) == .suppress)
assert(down(12) == nil) // Ordinary Command-Q is untouched outside the picker.
keys.configure(enabled: true, activation: "option", columns: 1)
assert(down(48, option: true) == .advance(reverse: false))
assert(keys.flagsChanged(command: false, option: true) == nil) // Track Option, even if Command was also held.
assert(down(125, command: false, option: true) == .move(1))
let beforeCancel = keys.epoch
assert(down(53, command: false, option: true) == .cancel)
assert(keys.epoch != beforeCancel && !keys.active)
assert(keys.flagsChanged(command: false, option: false) == nil)
keys.reset()
for (code, action) in [(12, WindowSwitcherKeyPolicy.Action.quit), (13, .close), (36, .commit)] {
    assert(down(48, command: false, option: true) == .advance(reverse: false))
    assert(keys.keyUp(48) == .suppress)
    assert(down(code, command: false, option: true) == action && !keys.active)
    assert(down(code, command: false, option: true) == .suppress) // No repeat into the next app.
    assert(keys.keyUp(code) == .suppress)
    assert(keys.flagsChanged(command: false, option: false) == nil) // No second commit after Q/W/Enter.
}
assert(down(48, command: false, option: true) == .advance(reverse: false))
assert(keys.keyUp(48) == .suppress)
let beforeLostModifier = keys.epoch
assert(down(12, command: false, option: false) == .cancelAndPass)
assert(!keys.active && keys.epoch != beforeLostModifier)
assert(down(12, command: false, option: false) == nil)
assert(down(48, command: false, option: true) == .advance(reverse: false))
assert(keys.keyUp(48) == .suppress)
assert(down(0, command: false, option: true) == .cancelAndPass && !keys.active)
assert(down(48, command: false, option: true) == .advance(reverse: false))
assert(keys.keyUp(48) == .suppress)
assert(down(124, command: false, option: true, control: true) == .cancelAndPass && !keys.active)
assert(down(48, command: false, option: true) == .advance(reverse: false))
let queuedEpoch = keys.epoch
keys.configure(enabled: false, activation: "option", columns: 1)
keys.configure(enabled: true, activation: "option", columns: 1)
assert(keys.epoch != queuedEpoch && !keys.active)
keys.configure(enabled: false, activation: "option", columns: 1)
assert(down(48, command: false, option: true) == nil)
assert(keys.keyUp(48) == nil)
print("Passed stable cycling/thumbnail matching and switcher navigation, action/repeat, modifier and configuration-epoch checks; no real window actions ran.")
