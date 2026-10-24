# 8D and stereo-surround controls

Added 24 October 2026. The notch and Audio settings now expose per-app controls
for the existing public rotating-stereo and surround DSP paths. Both effects are
disabled by default. Controls edit the same manager settings used by the mixer;
they are not a separate preview state. Reset restores the app's defaults.

8D controls cover rotation speed, depth, distance effect, elevation/front-back
motion, room size/spread, bass boost, intensity and center focus. Surround
controls cover stereo width, crossfeed, ambience, depth and center focus. These
are stereo spatial effects. The UI reports whether the mixer currently has an
active tap for the app; that alone is not a claim of audible output or successful
effect processing. Per-app routing and system-audio capture permission still apply.

Settings types were extracted from MultiAudioManager while preserving Codable
keys and legacy initialization/decoding defaults. All numeric parameters now
normalize finite bounds at construction/decoding, manager reads/writes and tap
updates before reaching the renderer. Non-finite values use the existing defaults.
Parameter-only updates notify the UI and push parameters to existing taps;
capture reconciliation is still reserved for enable/disable changes.

`./scripts/test-spatial-audio.sh` tests legacy sparse decoding, defaults, every
parameter's invalid/extreme bounds, normalization idempotence and persistence
round trips. It starts no mixer, process tap or playback. Full app compilation
checks the controls, manager and renderer parameter wiring.

Actual permission approval/denial, live routing, saved changes while playing,
device changes, reset/teardown and acoustic/latency behavior remain attended
checks. No audio was played for these tests. These changes do not establish
upstream parity or certify discrete multichannel surround support.
