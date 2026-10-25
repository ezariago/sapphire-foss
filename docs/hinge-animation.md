# Bounded hinge snapshot effect

The public hinge-animation manager now has an opt-in implementation in **System →
Lid Hinge Animation**. It requires a supported reporting lid-angle sensor, exactly
one connected built-in display, an unlocked console session and Screen Recording
permission. Unsupported hardware or denied permission produces a status message;
there is no fabricated angle or dimming fallback.

A new sensor tick is required after startup, setting changes and interruptions;
readings older than half a second are rejected. After a valid open reading at least 5° beyond the configured activation angle,
closing below that angle starts one gesture. Sapphire captures one built-in display
snapshot with ScreenCaptureKit, scaled to a longest edge of at most 2048 pixels.
It keeps this image in memory and displays a nonactivating, mouse-transparent
panel whose dim/blur follows the measured angle and configured intensity/blur.
The dim opacity is capped at 0.7. This is a **frozen-image effect**, not a live
blurred desktop or continuous screen recording. The host desktop can continue to
change behind the image; the effect is deliberately short-lived.

Capture must finish within two seconds of gesture start, and the entire gesture
ends after at most four seconds, with a 200 ms maintenance check plus sensor ticks.
The actual deadline delivery depends on the main run loop being responsive.
Opening back above activation hides the effect; opening 5° beyond activation
rearms it. Timeout or capture failure requires opening again before another try.
Invalid/nonfinite/out-of-range readings, clock rollback, sensor failure,
configuration changes, lock, sleep/wake, display changes and shutdown discard the
image and invalidate old capture tickets. A result from an earlier gesture cannot
appear after disable/re-enable or restart. There is at most one outstanding native
capture request, even if the framework ignores Task cancellation; a stuck request
blocks further capture until it returns or the app restarts.

Only valid enabled configurations acquire sensor polling. Sampling uses standby
and active clients already supplied by LidAngleSensor, releasing them on teardown
and while capture permission/session/hardware gates are unavailable. Activation
angle (45–140°), intensity (0.5–1.5) and maximum blur (0–180 pt) are validated. No
snapshot is written to disk, clipboard, logs or phone by this path. Clearing Swift
references is not a guarantee of secure erasure from framework/GPU memory.

This does not change brightness, gamma, power settings or normal system sleep,
prevent lid sleep, authenticate anyone or supply a privacy/security shield. It
only affects the built-in display. Screen Recording is managed by the existing
permission UI/request path; tests do not request or change that permission.

## Verification and remaining work

`./scripts/test-hinge-animation.sh` compiles the production policy and asynchronous
engine. Synthetic readings/images exercise arming, dimensions, expiry, invalid
configuration/clock/sensor/permission/lock gates, old capture rejection,
disable/re-enable/restart, uncancellable single-flight capture, oversized capture
rejection and reentrant sensor callbacks. An additional fixture compiles the real
manager and native renderer/capture adapters against fake settings/sensor, checking
disabled/invalid configuration and subscription start/stop. It never captures the
desktop, presents a panel, acquires real hardware or changes real preferences.
The script is included in macOS CI.

A separate local `HardwareAvailability.swift --sample` check compiled the actual
LidAngleSensor and read one native report on this Mac (Mac14,2): standard sensor
found, reporting true and angle within 0–180°. Its sensor client was released
immediately afterward. This establishes one valid hardware report, not cadence
or a closing gesture; it is not part of the CI script.

Beyond the attended Mac check recorded below, broader sensor/OEM availability
and cadence, Screen Recording revocation, image accuracy, keyboard/mouse
transparency, full-screen/Spaces,
macOS lock/sleep notification ordering and performance remain unverified. Physical
Mac lid-close/sleep checks have not been performed. These require an attended
hardware smoke test; build success and injected fixtures do not establish them.
The README item therefore remains open.

The capture adapter uses Apple's [display content filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)
with the existing single-image ScreenCaptureKit API; it does not create a stream.

## Reported failure investigation (25 October 2026)

The running `/Applications/Sapphire.app` had different binary contents and omitted
this implementation’s status text. After normally quitting it and launching the
current local development build, System Enhance reported a live 111° sensor angle
and “Allow Screen Recording in Permissions before using hinge animation.” This
establishes a permission blocker in the current build, not a verified visual fix.
The hinge card now offers an explicit permission request button when the engine
reports that blocker. The Permissions Overview also retains an Allow button after
a denial. Either button requests access and opens the macOS Screen Recording pane
if access is still unavailable. It does not approve access automatically. If the
app is absent from that pane, use its + button to add the exact development app.
The user added and enabled the development app in macOS Settings. After a normal
restart its status changed to “Ready for a closing gesture,” with a live 108°
reading. The user then confirmed that dim/blur appeared during partial lowering
and cleared on reopening. Permission recognition, arming and this attended
visible gesture are verified on this Mac; no full lid-close/sleep test was
performed.

An attended-session read-only `HardwareAvailability.swift --cadence` probe also
sustained 20 standby sensor updates over two seconds; its largest observed gap was
0.122 seconds, within the half-second freshness limit. This probe requests no
screen image or lid movement and releases its sensor client on exit. It does not
establish visual capture or lid-close behavior.

The final local app build and hinge policy/engine/native-adapter checks passed.
After restarting that final build, its hinge status remained “Ready for a closing
gesture,” confirming permission survived the rebuild. The user’s adjusted
intensity setting was retained. The new permission-retry buttons compile; access
was not revoked merely to retest them.
