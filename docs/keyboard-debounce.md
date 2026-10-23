# Keyboard debounce

Added 2026-10-24, disabled by default. Enable in Mouse settings after granting
Accessibility permission. The public manager uses the shared event tap and the
existing global/per-key interval settings. It does not change keyboard firmware,
system repeat preferences or persistent device settings.

A repeated physical key press shortly after release is filtered together with its
matching release. A chatter burst extends that release interval. Accepted held
keys keep native autorepeat; a rejected press cannot start a repeat stream.
Duplicate non-repeat down events while a key is already held are rejected without
swallowing the accepted press's eventual release. Modifier combinations have
separate release matching, and a release is paired by physical keycode even if
modifiers changed while the key was held.

Global intervals are configurable from 20–150 ms. Advanced overrides use macOS
virtual keycodes and allow zero to leave a key unfiltered. State resets on
configuration changes, foreground-app changes, sleep/wake, event-tap reset and
teardown. Only keycodes, modifier masks and monotonic timing are held in memory;
no typed characters, text history or keystroke log is collected.

`./scripts/test-keyboard-bounce.sh` passes isolated chatter-pair/burst,
held-repeat, duplicate-down, modifier, independent-key, override, unmatched-up
and reset fixtures. No keyboard events are injected by the test. Full app builds
verify integration, not real hardware behavior.

Remaining checks: physical worn keyboards, rapid intentional repeated letters,
multiple keyboards, input methods, secure-input fields, synthetic paste and
shortcut/filter coexistence, Accessibility loss/recovery and actual sleep/wake.
The filter is global across keyboards and has no per-device discrimination or
per-app exclusion UI. [Extra-click filtering](mouse-click-filter.md) now has a public implementation.
Other mouse controls, focus follows mouse, Super Key, snippets and emoji
suggestions remain unimplemented.
