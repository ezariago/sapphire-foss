import Foundation
var policy = AutoQuitPolicy()
let app = "12345:launch-1"
assert(!policy.observe(app, windowCount: 0, now: 0))
assert(!policy.observe(app, windowCount: 0, now: 100)) // Never had windows.
assert(!policy.observe(app, windowCount: 1, now: 101))
assert(!policy.observe(app, windowCount: 0, now: 102))
assert(!policy.observe(app, windowCount: 0, now: 104.9))
assert(policy.observe(app, windowCount: 0, now: 105))
assert(!policy.observe(app, windowCount: 0, now: 200)) // No repeated quit request.
policy.reset()
assert(!policy.observe(app, windowCount: 1, now: 0))
assert(!policy.observe(app, windowCount: 0, now: 1))
assert(!policy.observe(app, windowCount: nil, now: 3)) // AX query failed.
assert(!policy.observe(app, windowCount: 0, now: 100)) // New grace interval, not instant quit.
assert(!policy.observe(app, windowCount: 0, now: 102.9))
assert(policy.observe(app, windowCount: 0, now: 103))
assert(!policy.observe(app, windowCount: 1, now: 104))
assert(!policy.observe(app, windowCount: 0, now: 105))
assert(!policy.observe(app, windowCount: 1, now: 107)) // Reopened window resets the grace period.
assert(!policy.observe(app, windowCount: 0, now: 110))
assert(!policy.observe(app, windowCount: 0, eligible: false, now: 111))
assert(!policy.observe(app, windowCount: 0, now: 200)) // Exclusion discards historical evidence.
assert(!policy.observe(app, windowCount: 2, now: 201))
assert(!policy.observe(app, windowCount: 0, now: 202))
assert(!policy.observe(app, windowCount: 0, now: 200)) // Defensive clock rollback.
assert(!policy.observe(app, windowCount: -1, now: 204))
assert(!policy.observe(app, windowCount: 0, now: 210))
assert(policy.observe(app, windowCount: 0, now: 213))
let replacement = "12345:launch-2"
assert(!policy.observe(app, windowCount: 1, now: 220))
assert(!policy.observe(app, windowCount: 0, now: 221))
policy.retain([replacement])
assert(!policy.observe(replacement, windowCount: 0, now: 300)) // Reused PID is a new process.
assert(!policy.observe(app, windowCount: 0, now: 300)) // Pruned identity cannot inherit a deadline.
assert(!policy.observe(replacement, windowCount: 1, now: 301))
assert(!policy.observe(replacement, windowCount: 0, now: 302))
policy.reset() // Feature disable / permission loss / simulated lifecycle reset.
assert(!policy.observe(replacement, windowCount: 0, now: 400))
assert(!policy.observe(app, windowCount: 1, now: 0))
assert(!policy.observe(app, windowCount: 0, now: 1))
assert(!policy.observe(app, windowCount: 0, now: .infinity))
assert(!policy.observe(app, windowCount: 0, now: 100))
assert(policy.observe(app, windowCount: 0, now: 103))
print("Passed auto-quit grace, unknown-query, reopen, exclusion, process identity, retry and lifecycle-reset policy checks; no apps were quit.")
