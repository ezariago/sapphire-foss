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


The dispatcher now invalidates captured actions synchronously when relevant
settings change, before the debounced registration rebuild. The generation also
changes on provider replacement/removal, recording, Accessibility teardown and
shared event-tap reset. Execution resolves current planes/mappings/providers and
rechecks permissions, enabled state and binding identity. Disable/re-enable
cannot revive an older queued action. Unrelated settings preserve valid work.
External providers now resolve legacy collisions in sorted provider-name order;
planes and Snap Zones keep their existing precedence. This is a local conflict
rule, not an audit of other applications' global shortcuts.

`./scripts/test-shortcut-dispatcher.sh` compiles the production dispatcher against
inert settings/event/action dependencies. It verifies deletion/reassignment,
rapid disable/re-enable, provider/permission/recording/reset transitions,
deterministic conflicts, repeated/synthetic key bypass and valid delivery. It
constructs events in memory without OS hooks, key posting or real window actions.
Native layout/permission/recording and OS shortcut coexistence still need checks.
