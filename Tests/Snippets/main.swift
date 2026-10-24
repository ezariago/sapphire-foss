import Foundation

typealias Policy = SnippetExpansionPolicy
var gate = SnippetInputGate()
gate.configure(enabled: true); gate.foreground(123)
assert(gate.up(1, eligible: true) == nil) // No expansion from a release without its eligible down.
gate.down(1, eligible: true)
let ticket = gate.up(1, eligible: true)!
assert(gate.isCurrent(ticket))
gate.down(2, eligible: true)
assert(!gate.isCurrent(ticket))
gate.foreground(456)
assert(gate.up(2, eligible: true) == nil)
gate.down(1, eligible: false)
assert(gate.up(1, eligible: true) == nil)
gate.down(1, eligible: true, target: 999)
assert(gate.up(1, eligible: true) == nil)
gate.down(1, eligible: true); gate.invalidate()
assert(gate.up(1, eligible: true) == nil)
gate.down(1, eligible: true); gate.configure(enabled: false)
assert(gate.up(1, eligible: true) == nil)
gate.configure(enabled: true); gate.down(1, eligible: true)
assert(gate.up(2, eligible: true) == nil)
let rules: [Policy.Rule] = [.init(trigger: ";hi", replacement: "Hello"), .init(trigger: "brb", replacement: "Be right back"), .init(trigger: ";hi", replacement: "Duplicate")]
func match(_ text: String, after: Bool = true, selection: NSRange? = nil, using rules: [Policy.Rule] = rules) -> Policy.Match? {
    Policy.match(text: text, selection: selection ?? NSRange(location: text.utf16.count, length: 0), rules: rules, afterDelimiter: after)
}
assert(match(";hi ") == .init(range: NSRange(location: 0, length: 4), template: "Hello", suffix: " "))
assert(match("🙂 ;hi!")?.range == NSRange(location: 3, length: 4))
assert(match("brb\n")?.suffix == "\n")
assert(match("wordbrb ") == nil)
assert(match(";hi") == nil)
assert(match(";hi", after: false)?.range == NSRange(location: 0, length: 3))
assert(match(";hi ", selection: NSRange(location: 0, length: 4)) == nil)
assert(match("🙂;hi ", selection: NSRange(location: 1, length: 0)) == nil)
assert(match(";hi ", selection: NSRange(location: NSNotFound, length: 0)) == nil)
assert(match(";hi ", selection: NSRange(location: 999, length: 0)) == nil)
assert(match(";hi ", selection: NSRange(location: -1, length: 0)) == nil)
assert(match("brbbaz", after: false, selection: NSRange(location: 3, length: 0)) == nil)
assert(match(";hi ", using: [.init(trigger: ";hi", replacement: "x", enabled: false)]) == nil)
assert(!Policy.validTrigger("x") && !Policy.validTrigger("a b") && !Policy.validTrigger("ab\n"))
assert(match(";hi ", using: [.init(trigger: ";hi", replacement: String(repeating: "a", count: 16_385))]) == nil)
assert(match(";hi ", using: [.init(trigger: "hi", replacement: "short"), .init(trigger: ";hi", replacement: "long")])?.template == "long")
assert(match(";hi  ") == nil) // One delimiter only; do not expand arbitrary earlier tokens.
assert(match(";hi ", using: Array(repeating: rules[0], count: 1001)) == nil)
assert(match(String(repeating: "x", count: 1_000_001) + ";hi ") == nil)
let date = Date(timeIntervalSince1970: 0)
let locale = Locale(identifier: "en_US_POSIX")
let zone = TimeZone(secondsFromGMT: 0)!
var reads = 0
let rendered = Policy.render("{{date:yyyy-MM-dd}} {{time}} {{clipboard}} {{clipboard}}", date: date, locale: locale, timeZone: zone) { reads += 1; return "{{date}}" }
assert(rendered?.replacingOccurrences(of: "\u{202f}", with: " ") == "1970-01-01 12:00 AM {{date}} {{date}}" && reads == 1) // ICU may use a narrow no-break space before AM; clipboard contents stay literal.
assert(Policy.render("Plain {{unknown}}", date: date, locale: locale, timeZone: zone) { fatalError("Unexpected clipboard read") } == "Plain {{unknown}}")
assert(Policy.render("{{clipboard}}", date: date, locale: locale, timeZone: zone) { nil } == nil)
assert(Policy.render("{{clipboard}}", date: date, locale: locale, timeZone: zone) { String(repeating: "x", count: 16_385) } == nil)

let original = SnippetEditTransaction.Snapshot(text: ";hi ", selection: NSRange(location: 4, length: 0))
let edit = match(original.text)!
var state = original
var writes = 0
func apply(select: (NSRange) -> Bool, replace: (String) -> Bool, current: () -> Bool = { true }) -> Bool {
    SnippetEditTransaction.apply(original: original, match: edit, replacement: "Hello ", read: { state }, stillCurrent: current, select: select, replace: replace)
}
assert(apply(select: { state.selection = $0; return true }, replace: { text in
    writes += 1; state.text = (state.text as NSString).replacingCharacters(in: state.selection, with: text); return true
}))
assert(state.text == "Hello " && writes == 1)
state = original; writes = 0
assert(!apply(select: { _ in false }, replace: { _ in writes += 1; return true }))
assert(writes == 0 && state == original)
assert(!apply(select: { state.selection = $0; return true }, replace: { _ in writes += 1; return false }))
assert(writes == 1 && state == original) // Refusal restores only an unchanged selection/value.
state = original; writes = 0
assert(!apply(select: { state.selection = $0; state.text = "User changed this"; return true }, replace: { _ in writes += 1; return true }))
assert(writes == 0 && state.text == "User changed this")
state = original
assert(!apply(select: { _ in state.selection = NSRange(location: 1, length: 0); return true }, replace: { _ in writes += 1; return true }))
assert(writes == 0 && state.selection.location == 1) // No restoration over a user's new selection.
state = original
assert(!apply(select: { state.selection = $0; return true }, replace: { _ in writes += 1; return true }, current: { false }))
assert(state == original && writes == 0)
state = original
var current = true
assert(!apply(select: { state.selection = $0; current = false; return true }, replace: { _ in writes += 1; return true }, current: { current }))
assert(writes == 0 && state.text == original.text)
let unicode = Policy.render("🙂 {{date:yyyy}}", date: date, locale: locale, timeZone: zone) { fatalError("Unexpected clipboard read") }
assert(unicode == "🙂 1970")
print("Passed snippet boundaries, UTF-16 selections, duplicates, disabled/invalid rules, bounded templates and nonrecursive date/clipboard fixtures; no user text or clipboard was accessed.")
