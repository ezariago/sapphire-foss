# Command-key Hyper mapping

Added 24 October 2026, opt-in in Mouse settings. Choose Left Command or Right
Command to add Control, Option and Shift while that physical key is held. The
other Command key remains native. App exclusions are separate from the shared
mouse-feature exclusions. Accessibility permission is required.

The implementation adds modifier flags to existing keyboard, flags-changed,
mouse and wheel events before Sapphire's shortcut handlers. It preserves keycodes,
timestamps, device flags and routing metadata. It does not synthesize key presses,
install a persistent HID mapping, record typed text or retain a held-key latch.
The SDK's device-side Command masks distinguish the two keys; events without
that side identity are passed through. Source-key release naturally stops adding
flags, preserving any other physical modifiers still held. A tap has no separate
action; no Escape or Caps Lock event is generated.

Caps Lock remains unsupported because its latching behavior needs a different
implementation. A saved unsupported source is shown explicitly and passes
through until a supported Command key is chosen. Unknown/non-regular foreground
apps and excluded foreground apps are bypassed. An already-targeted event for a
different PID is also bypassed. Foreground notifications are cached on the main
queue; app transitions can race delivery and need native verification.

`./scripts/test-super-key.sh` checks side identity, both physical Command keys,
release/no-held-state behavior, preservation of other modifiers, unsupported
sources and unposted CGEvent transformations. It also verifies that Hyper-wheel
events bypass the mouse-wheel transform. These are not hardware-input tests.

Remaining manual checks include actual global shortcut routing, both Command
keys together, input methods, secure-input transitions, permission loss/recovery,
sleep/wake, app exclusions and coexistence with third-party remappers. The OS
controls event-tap delivery during secure input; the manager does not request
access to protected typing. Native app/OS modifier-state behavior has not been
verified from these fixtures alone. Use the opt-in setting only after those checks
for the intended keyboard and apps.
