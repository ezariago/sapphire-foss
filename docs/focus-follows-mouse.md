# Focus follows mouse

Added 2026-10-24, disabled by default. Mouse settings expose the enable switch,
0.1–2 second dwell delay and shared mouse-feature app exclusions. Accessibility
permission is required. This uses native AX window focus/raise and normal app
activation; no clicks, keyboard events or screenshots are synthesized.

The pointer must remain over an eligible window for the dwell interval. A new
window, typing, app activation, configuration changes or lifecycle reset restarts
that interval. Already-focused windows, Sapphire's own windows, menu elements
under the pointer, minimized windows and non-regular apps are skipped. Held mouse
buttons, shortcut modifiers, secure event input and an excluded current or target
app pause focusing. The manager rechecks trust, exclusions, frontmost app and
pointer location before attempting activation. Failures do not cause repeated
focus attempts on every timer tick of the same hover episode.

`test-hover-focus.sh` covers the isolated dwell state, target changes, one-shot
behavior, resets, clock rollback and invalid values without focusing apps. A
successful app build checks integration, not native behavior.

Remaining manual checks: actual AX permission loss/recovery, multiple displays,
Spaces/full-screen apps, menus/input methods, secure-input transitions, typing and
drag coexistence, app exclusions and actual sleep/wake. AX queries and app focus
are separate OS operations, so rapid external window changes can still race the
final checks. Physical sleep/lid-close testing was not performed overnight.
