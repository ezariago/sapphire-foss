# Mouse middle and side-button remapping

The public build now offers **Mouse → Remap middle and side clicks**, disabled by
default and independent of wheel customization. Configure middle button 3 and side
buttons 4/5, plus alternate actions with a selected keyboard modifier or one
reserved mouse modifier button. The underlying CG button numbers are 2/3/4.
The existing mouse exclusion list applies.

Supported actions request the foreground app's enabled menu item with its usual
shortcut: Back/Forward (⌘[/⌘]), Copy/Paste/Cut, Undo/Redo, Select All, Close Window,
Minimize, New Tab/Window, Reload and Full Screen. This is menu-command matching,
not semantic inspection: apps using different shortcuts, inaccessible menus or
no matching enabled item may decline an action. Sapphire reads command-equivalent
metadata and child/enable attributes, not menu titles, selection contents or the
clipboard. It invokes the native AX press action and posts no keyboard events.
The requesting app owns save dialogs and the resulting command behaviour.

Mission Control now requests the fixed `/System/Applications/Mission Control.app`
launcher after checking the expected `com.apple.exposelauncher` bundle identity.
It uses Launch Services, not a guessed shortcut, menu search, shell or private
Dock selector. The request is revalidated after target lookup and inherits the
same pairing, expiry, focus, secure-input and shield guards as menu actions.
Missing/mismatched targets or a declined open request report unavailable.
Acceptance by Launch Services is not proof that the overview became visible.

Keep native and unsupported saved actions pass through. Launchpad, Show Desktop, app switcher, Spotlight, Lock Screen and opening Sapphire
settings are not implemented by this remapper and are omitted from new choices.
Existing unsupported values are labelled rather than silently rewritten. A
remapped Close Window request is skipped where Sapphire's ⌘W protection applies,
so this route cannot intentionally bypass that policy. Original native mouse
behaviour is outside keyboard shortcut protection.

## Input and delivery guards

- Only buttons 3/4/5 can be mapped; left/right input is never swallowed here.
  A mapped down is consumed together with its up/drag events. Commands run once
  on release within two seconds and six screen points of the press. Mapped drags
  or long holds are cancelled and consumed. None/unmapped drags remain native.
- Exact configured keyboard-modifier combinations select alternate actions.
  Unrelated shortcut modifiers and Fn preserve native input. A mouse modifier
  button consumes its own click only when another button has a supported
  alternate action. It supplies no separate action while reserved. Configuring
  all alternate actions to Keep native leaves that button unreserved.
- Foreground identities include PID, bundle ID and launch date. Unknown,
  nonregular, Sapphire itself, excluded apps and mismatched target PIDs are
  declined. A zero event target PID cannot establish the app under the pointer:
  actions are defined for the foreground app, which can differ from a background
  window under the pointer. Cached activation notifications can race actual input.
- Settings, focus, session/sleep and event-tap resets invalidate old requests.
  Ordinary changes retain consumed-pair tombstones through release, cancelling
  actions. A tap reset clears tracking because input may have passed unobserved;
  shutdown/tap gaps cannot guarantee native pair balance across the gap.
- New typing, scrolling or native mouse clicks cancel pending work. This path
  observes keyboard event type for cancellation, not typed text or keycodes.
  Tagged synthetic mouse events bypass remapping. Secure input, permission loss,
  unavailable/locked console sessions, visible Sapphire shields and app changes
  prevent native command delivery.
- At most one main-queue delivery/AX lookup is pending. Rapid mapped clicks while
  busy can be skipped. Traversal is bounded by depth, node/child count and a
  400 ms budget, with 40 ms AX messaging timeouts. Slow native calls can overrun a
  polling deadline. Requests expire after one second and recheck context before
  pressing. There is no OS-wide atomic focus/configuration/AX transaction; a narrow
  external change between final checks and press remains possible.

## Verification and remaining work

`./scripts/test-mouse-buttons.sh` compiles the real policy, unposted CGEvent
adapter and asynchronous delivery lane. Fixtures cover pairing, drags/holds,
clock/configuration/focus/process changes, modifiers, exclusions, secure/synthetic/
target refusal, protected Close, bounded/late menu lookup and stale uncancellable
single-flight delivery. A second fixture compiles the actual native manager/AX
adapter against fake settings and inert hooks, exercising disabled/configuration/
reset/teardown/startup without installing a real tap or invoking real menus.
The script runs in macOS CI. No fixture posts input or reads/changes user clipboard
or document contents.

Real mouse hardware/driver numbering, Accessibility approval/revocation, native
menu availability, keyboard layouts/localized apps, background-pointer behaviour,
coexistence with drag/click filters, physical session transitions and actual app
commands still need attended checks. Pointer acceleration and smooth/linear
scrolling remain separate unimplemented features. This is a defined public subset,
not complete system-button or upstream parity.

## Mission Control request checkpoint — 25 October 2026

Injected tests now cover Mission Control policy selection/modifiers, expiry/
invalidation, fixed target identity, missing/wrong bundle, stale final validation
and accepted/declined launch requests. Native adapter compilation and a read-only
check of this Mac's installed system-app metadata pass. The full local Mac build
passes. No test launched Mission Control, posted keys or changed user windows.
Actual overview visibility and physical mapped-button behaviour remain native
checks. Other system actions remain unsupported rather than being mapped to
undocumented shortcuts or unrelated app interfaces.
