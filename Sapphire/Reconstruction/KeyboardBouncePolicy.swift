#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Tracks physical keycodes and modifier masks only; never reads typed text.
struct KeyboardBouncePolicy {
    private struct Held { let allowed: Bool; let modifiers: UInt64 }
    private struct Release { let time: TimeInterval; let modifiers: UInt64 }
    private var held: [Int: Held] = [:]
    private var released: [Int: Release] = [:]
    mutating func reset() { held.removeAll(); released.removeAll() }
    mutating func keyDown(_ key: Int, modifiers: UInt64, isRepeat: Bool, now: TimeInterval, interval: TimeInterval) -> Bool {
        guard (0...65535).contains(key), now.isFinite else { return true }
        let interval = interval.isFinite ? min(0.15, max(0, interval)) : 0
        if interval == 0 { held[key] = Held(allowed: true, modifiers: modifiers); return true }
        if let previous = held[key] {
            // Preserve native held-key repeat, but reject duplicate non-repeat downs.
            return isRepeat && previous.allowed
        }
        let bounce = released[key].map { previous in
            previous.modifiers == modifiers && now >= previous.time && now - previous.time < interval
        } ?? false
        let allowed = isRepeat || !bounce
        held[key] = Held(allowed: allowed, modifiers: modifiers)
        return allowed
    }
    mutating func keyUp(_ key: Int, modifiers: UInt64, now: TimeInterval) -> Bool {
        guard (0...65535).contains(key), now.isFinite else { return true }
        let previous = held.removeValue(forKey: key)
        released[key] = Release(time: now, modifiers: previous?.modifiers ?? modifiers)
        return previous?.allowed ?? true
    }
}
#endif
