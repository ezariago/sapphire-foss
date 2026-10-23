# Extra-click filtering

Added 2026-10-24, disabled by default. Enable Click debounce in Mouse settings
after granting Accessibility permission. The existing interval setting is
exposed from 10–60 ms, with exclusions for the current foreground application.
No mouse firmware or persistent system input preferences are changed.

A same-button press within the short release interval and four points of the
release position is treated as chatter. Its release and any drag stream are also
filtered, keeping button pairs consistent. Other buttons, changed modifiers,
clicks at a new position and clicks outside the threshold pass normally. An
accepted drag is preserved and its release does not seed a chatter deadline, so
a drop followed by a click is retained. Duplicate downs do not swallow the
original accepted press's release; unmatched releases pass through.

The shared event tap holds only button numbers, coordinates, modifier masks and
monotonic timing in memory. Configuration, foreground-app, sleep/wake, event-tap
reset and teardown clear state. Exclusions use the foreground app at event time;
they are not hit-tested per target window. Events are never synthesized and
native click-count metadata is not rewritten.

`test-mouse-click-bounce.sh` passes isolated pair/burst, position-boundary,
button/modifier isolation, drag/drop, duplicate-down, zero-interval, malformed
coordinate and reset fixtures. No mouse events are injected. The full app build
checks integration, not real device behavior.

A timing filter cannot distinguish every worn-switch bounce from a very fast
intentional click or the start of a drag. Use the smallest effective interval.
Real double/triple-click counts, drag initiation, multiple mice, excluded-app
transitions, other input tools and Accessibility/lifecycle recovery remain
manual checks. Other pointer controls and focus follows mouse remain unfinished.
