import Foundation
var policy = HoverFocusPolicy()
assert(!policy.observe(target: nil, now: 0, delay: 0.5))
assert(!policy.observe(target: "window-a", now: 0, delay: 0.5))
assert(!policy.observe(target: "window-a", now: 0.49, delay: 0.5))
assert(policy.observe(target: "window-a", now: 0.5, delay: 0.5))
assert(!policy.observe(target: "window-a", now: 10, delay: 0.5)) // No repeated focus attempts.
assert(!policy.observe(target: "window-b", now: 11, delay: 0.5))
assert(!policy.observe(target: "window-a", now: 11.4, delay: 0.5)) // Returning restarts the delay.
assert(!policy.observe(target: "window-a", now: 11.8, delay: 0.5))
assert(policy.observe(target: "window-a", now: 12, delay: 0.5))
policy.reset() // Input, configuration, lifecycle or permission reset.
assert(!policy.observe(target: "window-a", now: 12.1, delay: 0.5))
assert(!policy.observe(target: "window-a", now: 11, delay: 0.5)) // Clock rollback restarts the delay.
assert(policy.observe(target: "window-a", now: 11.5, delay: 0.5))
assert(!policy.observe(target: "window-a", now: .nan, delay: 0.5))
assert(!policy.observe(target: "window-a", now: 13, delay: .infinity))
assert(!policy.observe(target: "window-a", now: 14, delay: 0))
assert(policy.observe(target: "window-a", now: 14.11, delay: 0)) // Minimum safe delay.
print("Passed hover-focus dwell, target change, one-shot, reset, rollback and invalid-time fixtures; no apps were focused.")
