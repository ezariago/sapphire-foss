#if !SAPPHIRE_FULL_BUILD
import Foundation

/// Monotonic-time state machine shared by the real event tap and tests.
struct QuitProtectionPolicy {
    private var held: [String: TimeInterval] = [:]
    private var fired: Set<String> = []
    private var previousPress: [String: TimeInterval] = [:]
    mutating func keyDown(key: String, mode: String, now: TimeInterval,
                          holdInterval: TimeInterval, doubleInterval: TimeInterval,
                          isRepeat: Bool, hasExtraModifier: Bool) -> Bool {
        if mode == "extraModifier" { return hasExtraModifier }
        if mode == "doublePress" {
            if isRepeat { return false }
            if let previous = previousPress.removeValue(forKey: key), now - previous <= max(0.1, doubleInterval) { return true }
            previousPress[key] = now
            return false
        }
        if fired.contains(key) { return false }
        if held[key] == nil { held[key] = now }
        if now - held[key, default: now] >= max(0.2, holdInterval) {
            fired.insert(key)
            return true
        }
        return false
    }
    mutating func keyUp(key: String) { held[key] = nil; fired.remove(key) }
    mutating func releaseHeldKeys() { held.removeAll(); fired.removeAll() }
    mutating func reset() { held.removeAll(); fired.removeAll(); previousPress.removeAll() }
}
#endif
