# Shared shortcut configuration

Added 24 October 2026. Keyboard Shortcuts now lists clipboard, Emoji & Symbols,
OCR, fixed App Lock privacy, Dock presets, planes and existing Snap Zone bindings
managed by the shared dispatcher. Other features retain their own shortcut UI.
Feature enable switches remain independent of the per-action Allow shortcut
switch. Nonoptional bindings can be disabled; optional plane/Dock bindings can
be cleared, and clearing a Snap Zone binding removes that mapping.

Recording requires Command, Control or Option and a translatable key for the
current layout. A conflicting enabled catalog binding is identified rather than
silently replaced. Writes resolve the current target by ID; deleting a plane,
zone mapping or preset during recording cannot recreate it from a stale row.
The recording overlay is cancelled if this view disappears, without stopping
another feature's recorder. Fixed App Lock privacy keeps its existing key.

Mapping diagnostics query the dispatcher's current trigger/action table under
its existing lock. They report configuration only. A mapped action is not proof
of Accessibility approval, external OS/app conflicts or native delivery. The
view explains missing permission and offers the existing user-invoked permission
action; opening the view does not request access or run any shortcut action.

The full app build verifies settings/dispatcher wiring. Existing Dock shortcut
policy fixtures remain relevant; no synthetic keys or actual window/Dock actions
are sent by configuration verification. Native recording, keyboard layouts,
collision resolution, disable/re-enable, input permission and key routing remain
attended checks. The catalog is not a claim that every upstream shortcut manager
has been reconstructed.


Source review found a remaining shared-dispatcher lifecycle issue: `perform`
queues captured plane/Snap Zone actions and only rechecks their disabled IDs.
Deleting or reassigning a target between key capture and main-queue execution
can therefore leave a stale queued action. External provider lifecycle guards
also vary: Emoji and Dock have additional validation, while the clipboard
provider only rechecks feature enablement. Provider iteration order is not a
stable collision priority. These are remaining implementation work, distinct
from the catalog's stale-safe configuration writes; they have not been fixed
or exercised with native input in this checkpoint. Add isolated lifecycle
fixtures before changing routing, then verify permission/recording transitions.
