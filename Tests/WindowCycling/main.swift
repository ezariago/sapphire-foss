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
print("Passed stable window cycling, AX reorder, close/open, app isolation and unambiguous thumbnail matching checks.")
