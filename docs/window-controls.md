# Public window and Dock implementations

Added 2026-10-24. All controls remain opt-in.

| Path | Implementation | Evidence and remaining work |
| --- | --- | --- |
| Dock presets | Capture pinned applications and Dock position/size/autohide/magnification; validated, versioned import/export; atomic preference backup before application; restart Dock | Isolated preference-domain tests pass. Actual Dock appearance and restoration need a manual smoke test. Legacy name-only presets cannot be applied until recaptured. Preset shortcuts can be recorded/cleared, persist locally and use the shared conflict-aware dispatcher; real key routing remains manual. |
| Window switcher | AX window enumeration, Command/Option-Tab cycling, reverse cycling, modifier-release activation, Escape cancellation | Full app compiles. Accessibility permission and real input/Spaces behavior remain manual checks. |
| Dock previews | AX Dock item hit testing and delayed window picker; ScreenCaptureKit window thumbnails when Screen Recording is allowed; icon/title fallback otherwise | Full app compiles. Alternate trigger/layout variants and live thumbnail refresh remain open. |
| Dock clicks | Minimize or hide a frontmost app after its Dock icon is clicked; cycle through a stable ring of windows starting after the focused AX window, including reordered/new/closed windows; delayed actions recheck app focus, exclusions and selected action | Isolated cycle and thumbnail-association tests pass; full app integration compiles. Real Dock timing, Accessibility approval and alternate-display behavior need manual checks. |
| Auto-quit | Track apps that had windows; request normal termination after their last window remains closed; excluded apps and AX-query failures are respected | No force termination. Save dialogs remain under the target app's control. Manual app compatibility checks remain open. |
| Quit/close protection | Shared event hook with hold, double-press and extra-modifier policies, app exclusions and per-close configuration | Isolated state-machine tests pass for timing, repeat suppression and app isolation. Hold uses keyboard repeat events; actual keyboard/input-method verification remains open. Menu/app-initiated exits are outside this hook. |
| Green maximize | Cached AX green-button hit; maximize to the display's usable frame and restore previous geometry; Option-click/full-screen exit keep native behavior | Full app compiles. Real button roles, app size constraints and multi-monitor hot-plug need manual verification. |

`./scripts/test-dock-layouts.sh` and `./scripts/test-quit-protection.sh` are included
in macOS CI. The former uses a fresh UUID-named CFPreferences domain and does not
change the real Dock. Context-menu services, hinge animations and Dock locking remain on the README
roadmap. A successful compile
is not recorded as end-to-end feature parity.

Window identities now follow AX element identity across enumeration rather than
array offsets or potentially duplicated window titles. Preview association uses
application/layer filtering and available title/geometry, and declines ambiguous
matches. Identical untitled windows therefore keep distinct picker identities;
an ambiguous thumbnail falls back to the app icon rather than guessing.

`./scripts/test-window-cycling.sh` covers AX-style reordering, wraparound, windows
opening/closing, missing focus information, per-app isolation, duplicate input
IDs, missing CG titles, geometry tolerance and ambiguous preview candidates. It
uses isolated records, not the user's windows. These checks do not prove real AX
identity behavior, Dock click delivery, cross-Space activation or ScreenCaptureKit
thumbnail capture; those remain manual permission/session checks.

Preset shortcut configuration now supports a recorded key with Command, Option
or Control, a clear action, and unavailable/disabled warnings. Unsupported keys
are reported by the shared shortcut dispatcher rather than silently ignored.
Invocations resolve the current preset and recheck enabled/disabled status,
preset existence and the expected shortcut before applying. Deleted or reassigned
presets cannot be applied by a stale queued shortcut action. Applying keeps the
existing validation, backup and Dock-restart behavior.

The optional shortcut field is backward compatible with existing local presets.
Export preserves it, while importing deliberately clears shortcut bindings and
assigns fresh IDs on collision; importing a file cannot silently install a global
hotkey or replace another preset. `test-dock-layouts.sh` now also covers shortcut
roundtrips, unsafe bare/Shift-only key rejection, disabled/deleted/reassigned
action guards and import sanitation. Tests use a fresh CFPreferences domain;
no real Dock was changed or restarted. Real shortcut routing, permission denial,
conflicts with other apps and actual Dock appearance still need an unlocked Mac.
