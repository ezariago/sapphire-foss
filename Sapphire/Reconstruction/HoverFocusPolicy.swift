#if !SAPPHIRE_FULL_BUILD
import Foundation

struct HoverFocusPolicy {
    private var target: String?
    private var since: TimeInterval = 0
    private var fired = false
    mutating func reset() { target = nil; fired = false }
    mutating func observe(target: String?, now: TimeInterval, delay: TimeInterval) -> Bool {
        guard let target, now.isFinite, delay.isFinite else { reset(); return false }
        let delay = min(2, max(0.1, delay))
        if self.target != target || now < since {
            self.target = target; since = now; fired = false
        }
        guard !fired, now - since >= delay else { return false }
        fired = true
        return true
    }
}
#endif
