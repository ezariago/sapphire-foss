# Mouse-wheel controls

Added 24 October 2026. Mouse settings expose opt-in vertical/horizontal wheel
inversion and 0.25–4× speed. The shared Accessibility event tap changes discrete
wheel deltas in place; it never posts replacement input or changes persistent
system preferences. All three delta representations are transformed consistently.
Integer-only consumers retain at least one step, so fractional speed changes are
quantized in those apps. Fixed-point and integer results saturate at their field
bounds rather than overflowing.

Continuous scrolling, phase/momentum gestures, and scrolling with Command,
Control, Option or Shift retain native behavior. This includes trackpad gestures
and devices that report continuous scroll, including some mice. Third-axis fields,
event timestamps, flags and routing metadata are preserved. Default speed with
neither inversion is a pass-through.

The shared mouse exclusion list applies to the **foreground** regular app, not
necessarily the window under the pointer. Unknown/non-regular foreground apps
are skipped. If an event already has a target PID that differs from the cached
foreground PID, it is also skipped. Foreground changes are observed on the main
queue, so notification delivery and actual input can race; background-window
scrolling and excluded-app transitions need manual checks. No target app is
queried synchronously on the event-tap thread.

`./scripts/test-mouse-scroll.sh` checks speed/direction, fractional deltas,
zero/invalid/extreme values and real unposted CGEvent objects, verifying the
delta fields, metadata retention and gesture/modifier bypasses. It does not send
scrolling to a real app. Native wheels, continuous mice, horizontal scroll,
excluded apps, permission loss/recovery, sleep/wake and third-party app behavior
remain manual verification. This does not implement pointer acceleration, button
remapping, smooth/linear scrolling or Super Key.
