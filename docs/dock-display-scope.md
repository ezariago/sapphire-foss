# Display scoping for Sapphire Dock enhancements

The existing display-lock settings now control public Dock previews and custom
Dock click actions. In **Dock Layouts → Display for Sapphire Dock enhancements**,
enable the limit and select a connected display. The picker uses the same saved
display identity scheme as Sapphire's other display settings, with runtime IDs
shown only to distinguish connected displays with the same label.

This limits Sapphire's actions. It does not move or pin the native macOS Dock,
change display arrangements, restart Dock, set Dock preferences or change Spaces.
The keyboard window switcher and applying saved Dock presets remain independent.

## Behavior

- With the limit off, actions may run on any uniquely identified connected
  display under the pointer. With it on, only the selected display is eligible.
  No selection, an absent display or ambiguous matching identity disables these
  enhancements instead of selecting another display. Legacy keys resolve only
  when unique; the Settings picker permits reselection without silently migrating
  an ambiguous key. Overlapping/mirrored pointer geometry is declined.
- Settings changes and changes to display identities, geometry or usable frames
  invalidate interaction generations. Existing preview panels are dismissed and
  old delayed Dock click actions cannot run after disconnect/reconnect or a
  disable/re-enable cycle. Preview configuration is rechecked around AX queries.
- Workspace sleep/wake, screen-lock/unlock notifications and teardown invalidate
  pending work. Current console-session/lock checks also gate interactions.
  These use the existing CG session state convention, not an OS security boundary.
- Picker placement now clamps its frame to the usable display area and shrinks
  it for smaller screens. This prevents the previous fixed-size origin calculation
  from placing it outside a small display. Full usability at extreme sizes still
  requires visual checks.

## Evidence and pending checks

`./scripts/test-dock-display-scope.sh` compiles the production scope state and
placement policy. Synthetic display fixtures cover negative origins, reordered
screen lists, exact and legacy identity, duplicate keys/runtime IDs, ambiguous
mirrored geometry, disconnect/reconnect, settings and suspension generations,
invalid/nonfinite geometry and small-screen placement. Dock preset and window
cycling regressions also run. No physical displays, Dock preferences or real
application windows are modified by these tests. The scope test is in macOS CI.

An additional read-only fixture compiles the production native adapter with fake
settings and the real display-identity extension. It verifies startup/refresh,
synchronous configuration invalidation, current screen/session readback and
stop/restart subscription behavior without installing input monitors or changing
real preferences. It does not simulate OS lock or hot-plug notifications.

The full app build checks wiring to the real Settings subscriber, native screen/
session adapters, preview controller, delayed click handlers and configuration UI.
Real pointer delivery, display hot-plug, mirrored/Spaces/OEM identity behavior,
permission changes, lock recovery and visual placement remain manual checks.
Physical Mac sleep/lid-close testing has not been performed. This is not native
Dock placement locking or a claim of complete upstream parity.
