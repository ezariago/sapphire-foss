# Public window and Dock implementations

Added 2026-10-24. All controls remain opt-in.

| Path | Implementation | Evidence and remaining work |
| --- | --- | --- |
| Dock presets | Capture pinned applications and Dock position/size/autohide/magnification; validated, versioned import/export; atomic preference backup before application; restart Dock | Isolated preference-domain tests pass. Actual Dock appearance and restoration need a manual smoke test. Legacy name-only presets cannot be applied until recaptured. Preset shortcuts can be recorded/cleared, persist locally and use the shared conflict-aware dispatcher; real key routing remains manual. |
| Window switcher | AX window enumeration, Command/Option-Tab cycling, reverse cycling, modifier-release activation, Escape cancellation | Full app compiles. Accessibility permission and real input/Spaces behavior remain manual checks. |
| Dock previews | AX Dock item hit testing and delayed window picker; ScreenCaptureKit window thumbnails when Screen Recording is allowed; icon/title fallback otherwise | Full app compiles. Grid/list/carousel layouts, larger thumbnails, compact title lists above six windows, and hover/middle-click/Option-click triggers now have public code. Live thumbnail refresh and real input/permission checks remain open. |
| Dock clicks | Minimize or hide a frontmost app after its Dock icon is clicked; cycle through a stable ring of windows starting after the focused AX window, including reordered/new/closed windows; delayed actions recheck app focus, exclusions and selected action | Isolated cycle and thumbnail-association tests pass; full app integration compiles. Real Dock timing, Accessibility approval and alternate-display behavior need manual checks. |
| Auto-quit | Track apps that had windows; request normal termination after their last window remains closed; excluded apps and AX-query failures are respected | No force termination. Save dialogs remain under the target app's control. Manual app compatibility checks remain open. |
| Quit/close protection | Shared event hook with hold, double-press and extra-modifier policies, app exclusions and per-close configuration | Isolated state-machine tests pass for timing, repeat suppression and app isolation. Hold uses keyboard repeat events; actual keyboard/input-method verification remains open. Menu/app-initiated exits are outside this hook. |
| Green maximize | Cached AX green-button hit; maximize to the display's usable frame and restore previous geometry; Option-click/full-screen exit keep native behavior | Full app compiles. Real button roles, app size constraints and multi-monitor hot-plug need manual verification. |

`./scripts/test-dock-layouts.sh` and `./scripts/test-quit-protection.sh` are included
in macOS CI. The former uses a fresh UUID-named CFPreferences domain and does not
change the real Dock. [Selection Services](selection-services.md) now implement
explicit text cleanup and URL tracking removal. Native Services discovery and
editor interaction, hinge animations and Dock locking remain on the README
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

The window switcher also honors its grid/list/carousel selection. Keyboard
selection scrolls into view, including reverse selection when first opening.
Dock preview controls are exposed in Dock settings. List mode uses app icons and
window titles without requesting thumbnail capture; compact mode switches to that
list above six windows. Enhanced mode requests larger snapshot thumbnails.
Middle-click means mouse button 2; Option-click requires Option without other
shortcut modifiers. Click triggers observe the event and preserve native Dock
behavior. The custom Dock minimize/hide/cycle action skips the preview's
Option-click gesture so those two Sapphire actions do not run together.

These UI and monitor paths passed a full local build, but were not exercised in
the locked overnight session. All layouts, trigger delivery, native click
coexistence, initial/reverse scrolling and capture permission changes still need
manual visual/input checks. Thumbnails are snapshots, not a live stream.
Arrow keys now move selection (up/down by three items in the grid and one in
list/carousel); Return activates. W requests closing the selected window through
its AX close button; Q requests normal application termination, excluding
Sapphire and essential system apps. Both dismiss the picker and respect native
save dialogs. There is no force termination. These commands still require real
input/permission and app-compatibility verification, including quit protection.

The switcher input policy tracks the activation modifier, suppresses repeats and
key-up events of consumed commands, and cancels safely if a modifier-release
event was missed. Input actions run in main-queue FIFO order, with configuration
epoch checks preventing old queued actions after disable/re-enable or event-tap
reset. Isolated `test-window-cycling.sh` fixtures cover navigation, command/repeat
suppression, modifier choice, lost-release recovery, cancellation and epoch
invalidation. No real application was closed or quit by these tests.

Unsupported keys and Control-modified commands cancel the switcher and pass
through to macOS; they cannot leave a pending selector commit behind. Fixtures
also cover these cancellation/pass-through paths.

Auto-quit now measures its grace period using monotonic uptime and requires
consecutive valid empty samples after observing at least one window. An AX error
breaks that sequence and starts a fresh grace period at the next empty sample;
it cannot leave an old deadline ready to fire. Reopening a window clears the
deadline. Excluded/terminated processes are pruned, and state keys include launch
time to distinguish reused PIDs; apps without a known launch date are skipped.
Feature/exclusion changes, permission loss, sleep/wake and teardown reset state.
Each empty episode requests termination once and never escalates to force quit.

`test-auto-quit.sh` exercises these state transitions, process replacement,
invalid/rollback clock values and reset behavior using isolated observations.
It does not close or quit any real apps. Sampling cannot observe windows that
open and close entirely between polls. Actual save-dialog refusal, AX failures,
sleep/wake and third-party compatibility still require manual verification.
