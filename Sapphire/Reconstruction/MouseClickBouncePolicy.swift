#if !SAPPHIRE_FULL_BUILD
import Foundation
import CoreGraphics

/// A short release-to-press filter; never synthesizes pointer or button events.
struct MouseClickBouncePolicy {
    private struct Held { let allowed: Bool; let modifiers: UInt64; var dragged = false }
    private struct Release { let time: Double; let point: CGPoint; let modifiers: UInt64; let eligible: Bool }
    private var held: [Int: Held] = [:]
    private var released: [Int: Release] = [:]
    mutating func reset() { held.removeAll(); released.removeAll() }
    mutating func down(_ button: Int, at point: CGPoint, modifiers: UInt64, now: Double, interval: Double) -> Bool {
        guard valid(button, point, now) else { held[button] = nil; released[button] = nil; return true }
        let interval = interval.isFinite ? min(0.06, max(0, interval)) : 0
        if interval == 0 { held[button] = Held(allowed: true, modifiers: modifiers); return true }
        if held[button] != nil { return false } // Duplicate down; keep the original release paired.
        let bounce = released[button].map { previous in
            let dx = point.x - previous.point.x, dy = point.y - previous.point.y
            return previous.eligible && previous.modifiers == modifiers && now >= previous.time
                && now - previous.time < interval && dx * dx + dy * dy <= 16
        } ?? false
        held[button] = Held(allowed: !bounce, modifiers: modifiers)
        return !bounce
    }
    mutating func drag(_ button: Int) -> Bool {
        guard var state = held[button] else { return true }
        state.dragged = true
        held[button] = state
        return state.allowed
    }
    mutating func up(_ button: Int, at point: CGPoint, modifiers: UInt64, now: Double) -> Bool {
        guard valid(button, point, now) else { held[button] = nil; released[button] = nil; return true }
        let previous = held.removeValue(forKey: button)
        released[button] = Release(time: now, point: point, modifiers: previous?.modifiers ?? modifiers,
                                   eligible: previous.map { !$0.dragged } ?? false)
        return previous?.allowed ?? true
    }
    private func valid(_ button: Int, _ point: CGPoint, _ time: Double) -> Bool {
        (0...31).contains(button) && point.x.isFinite && point.y.isFinite && time.isFinite
    }
}
#endif
