import Foundation
func screen(_ id: String, key: String? = nil, aliases: [String] = [], x: Double = 0, y: Double = 0, width: Double = 1000, height: Double = 800) -> DockScopeDisplay {
    let frame = CGRect(x: x, y: y, width: width, height: height)
    return .init(id: id, key: key ?? id, aliases: aliases, name: "Fixture " + id, frame: frame, visibleFrame: frame.insetBy(dx: 10, dy: 20))
}
let left = screen("1", key: "serial-left", aliases: ["legacy-left"], x: -1000)
let right = screen("2", key: "serial-right", aliases: ["legacy-right"])
var state = DockDisplayScopeState(), config = DockScopeConfiguration()
state.update(configuration: config, displays: [left, right])
assert(state.ticket(at: .zero) == nil) // Starts suspended.
state.setSuspended(false)
let leftTicket = state.ticket(at: CGPoint(x: -500, y: 20))!
assert(state.accepts(leftTicket) && state.ticket(at: CGPoint(x: 500, y: 20)) != nil)
assert(state.ticket(at: CGPoint(x: -1001, y: 20)) == nil)
assert(state.ticket(at: CGPoint(x: 1000, y: 20)) == nil)
assert(state.ticket(at: CGPoint(x: Double.nan, y: 20)) == nil)
let unchanged = state.epoch
state.update(configuration: config, displays: [right, left])
assert(state.epoch == unchanged) // Enumeration order is not a topology change.
config.locked = true
state.update(configuration: config, displays: [left, right])
assert(state.ticket(at: CGPoint(x: 500, y: 20)) == nil && !state.accepts(leftTicket))
config.selectedDisplay = "serial-left"
state.update(configuration: config, displays: [left, right])
assert(state.selected == left && state.ticket(at: CGPoint(x: -500, y: 20)) != nil)
assert(state.ticket(at: CGPoint(x: 500, y: 20)) == nil)
let selected = state.ticket(at: CGPoint(x: -500, y: 20))!
state.update(configuration: config, displays: [right])
assert(state.selected == nil && !state.accepts(selected))
state.update(configuration: config, displays: [left, right])
assert(!state.accepts(selected)) // Reconnect does not revive queued work.
config.selectedDisplay = "legacy-left"
state.update(configuration: config, displays: [left, right]); assert(state.selected == left)
let conflicting = screen("3", key: "other", aliases: ["legacy-left"], x: 1000)
state.update(configuration: config, displays: [left, right, conflicting]); assert(state.selected == nil)
config.selectedDisplay = "serial-left"
let duplicateKey = screen("3", key: "serial-left", x: 1000)
state.update(configuration: config, displays: [left, duplicateKey]); assert(state.selected == nil)
state.update(configuration: config, displays: [left, left]); assert(state.ticket(at: CGPoint(x: -500, y: 20)) == nil)
config.locked = false
state.update(configuration: config, displays: [screen("1"), screen("2")])
assert(state.ticket(at: CGPoint(x: 500, y: 20)) == nil) // Ambiguous mirrored geometry.
state.update(configuration: config, displays: [left, right])
let beforeSettings = state.ticket(at: CGPoint(x: 20, y: 20))!
config.clicks = true; state.update(configuration: config, displays: [left, right])
config.clicks = false; state.update(configuration: config, displays: [left, right])
assert(!state.accepts(beforeSettings)) // Disable/re-enable/configuration ABA.
let beforeSleep = state.ticket(at: CGPoint(x: 20, y: 20))!
state.setSuspended(true); assert(state.ticket(at: CGPoint(x: 20, y: 20)) == nil)
state.setSuspended(false); assert(!state.accepts(beforeSleep))
let beforeMove = state.ticket(at: CGPoint(x: 20, y: 20))!
state.update(configuration: config, displays: [left, screen("2", key: "serial-right", y: 100)])
assert(!state.accepts(beforeMove))
state.update(configuration: config, displays: [screen("bad", width: 0)])
assert(state.ticket(at: .zero) == nil)
state.update(configuration: config, displays: [screen("bad", x: Double.greatestFiniteMagnitude, width: Double.greatestFiniteMagnitude)])
assert(state.ticket(at: .zero) == nil)
for frame in [CGRect(x: -1000, y: -800, width: 1000, height: 800), CGRect(x: 20, y: 30, width: 300, height: 200)] {
    for point in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: frame.midX, y: frame.midY)] {
        let placement = DockDisplayScopeState.panelFrame(size: CGSize(width: 700, height: 430), near: point, visibleFrame: frame)!
        assert(frame.contains(placement) && placement.width <= 700 && placement.height <= 430)
    }
}
assert(DockDisplayScopeState.panelFrame(size: .zero, near: .zero, visibleFrame: right.frame) == nil)
print("Passed real Dock display identity/scope, ambiguity/disconnect/reconnect, configuration/suspension/topology epoch, finite-geometry and small-screen picker placement checks. No Dock, displays, apps or user settings were changed.")
