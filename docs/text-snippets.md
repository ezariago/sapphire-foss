# Text snippets

Added 24 October 2026. Enable in Clipboard → Text Snippets and add an enabled
trigger/replacement. Expansion is disabled by default. The existing setting
selects expansion after a space/punctuation delimiter or immediately after a
trigger completes. Delimiters are retained. Triggers are case-sensitive, must
have 2–64 UTF-16 units without whitespace/control characters, and require a
word/punctuation boundary before them. Longest matches win; duplicate enabled
triggers use the first valid rule. More than 1,000 rules disables expansion until
the list is reduced. Invalid triggers and oversized replacements are skipped.

The manager observes eligible key-down/up pairs through the shared event tap;
it never swallows or synthesizes typing. Return/Tab, navigation/delete keys,
held-key repeats and Command/Control/Option chords do not trigger expansion.
App changes, clicks, modifier changes, settings changes, sleep/wake, teardown and
event-tap resets invalidate pending work. A key release without its matching
eligible press cannot expand pre-existing text in a newly focused app.

Expansion uses Accessibility on the focused regular app's editable text field,
text area or combo box. Sapphire's own fields, secure/password subroles, protected
content, active secure input, selected text and unsupported/non-writable fields
are skipped. Editors exposing a nonempty marked-text range are skipped during
input-method composition. Other custom editors may not expose enough information
to support this feature. Permission is never requested from a background test.

The field's value/caret and focus/configuration/input ticket are rechecked before
selecting the matched range and again before writing selected text. A refused
write restores the previous selection only if focus, value and selected range
remain unchanged. No whole-field replacement, clipboard write or synthetic-paste
fallback is used. AX operations on another process cannot be made atomic: rapid
external changes can still race separate OS calls. Actual input methods and
third-party editing/undo behavior remain manual checks.

Supported placeholders are `{{date}}`, `{{time}}`, `{{date:MMMM d}}` (custom date
format up to 100 characters) and `{{clipboard}}`. Date/time use the current
locale/time zone. Clipboard text is read only for a matched expansion containing
that placeholder, at most once per expansion; missing/non-text or oversized
clipboard content cancels expansion. Inserted clipboard text is literal and is
not recursively interpreted. Unknown placeholders remain literal. Templates and
the final expanded result including delimiter are capped at 16,384 UTF-16 units.
Fields over one million UTF-16 units are skipped. Field contents are temporary
in-memory reads for matching/revalidation and are not logged or persisted.

`./scripts/test-snippets.sh` covers trigger boundaries, Unicode/UTF-16 selections,
duplicates/disabled rules, malformed and bounded inputs, locale-aware placeholders,
lazy nonrecursive clipboard insertion, input/app/configuration invalidation and
refusal/race-safe edit transactions. Fixtures use only synthetic strings and
injected clipboard access; no user field or clipboard is accessed.

`./scripts/test-snippets-native.sh` also passed on this Mac: it launches a temporary
background fixture without activating it, performs real cross-process AX
range/selected-text replacement in its plain NSTextView and verifies the fixture's
secure-field subrole. Only synthetic fixture text is touched. The fixture is
terminated afterward and has a 30-second fallback exit. The driver exits 77
without requesting permission if AX access is unavailable; it is not run on
headless CI. This proves those native setters on a standard background text view,
not global keystroke routing or secure-field enforcement. Actual secure fields,
input methods, foreground routing, undo and third-party compatibility still need
attended verification before claiming full support.
