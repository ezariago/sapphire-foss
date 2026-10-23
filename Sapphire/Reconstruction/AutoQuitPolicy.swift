#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Requires an observed nonempty app, then consecutive valid empty samples
/// spanning the grace period. Keys include launch identity, not just a reusable PID.
struct AutoQuitPolicy {
    private struct Observation { var hadWindows = false; var emptySince: TimeInterval? }
    private var observations: [String: Observation] = [:]
    let grace: TimeInterval
    init(grace: TimeInterval = 3) { self.grace = max(0, grace) }
    mutating func retain(_ liveKeys: Set<String>) {
        observations = observations.filter { liveKeys.contains($0.key) }
    }
    mutating func reset() { observations.removeAll() }
    mutating func observe(_ key: String, windowCount: Int?, eligible: Bool = true, now: TimeInterval) -> Bool {
        guard eligible else { observations.removeValue(forKey: key); return false }
        var state = observations[key] ?? Observation()
        guard let count = windowCount, count >= 0, now.isFinite else {
            state.emptySince = nil // An AX error is not a valid empty observation.
            observations[key] = state
            return false
        }
        if count > 0 {
            state.hadWindows = true
            state.emptySince = nil
        } else if state.hadWindows {
            if let since = state.emptySince, now >= since, now - since >= grace {
                observations.removeValue(forKey: key) // One request until another window is seen.
                return true
            }
            if let since = state.emptySince {
                if now < since { state.emptySince = now }
            } else { state.emptySince = now }
        }
        observations[key] = state
        return false
    }
}
#endif
