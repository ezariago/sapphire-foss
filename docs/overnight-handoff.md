# Overnight handoff — 24 October 2026

The README roadmap is **unfinished**. Overnight work added public implementations
and regression fixtures to previously missing paths. A buildable feature is not
proof of upstream parity, complete source provenance or native device behavior.
Unattended implementation stopped at 07:00 Asia/Jakarta. The automation is paused
and the phone was verified Dozing after `KEYCODE_SLEEP`; its final stop record is
in [overnight progress](overnight-progress.md).

## Implementations and evidence

| Area | Implemented this session | Evidence and remaining limits |
| --- | --- | --- |
| Foundation | FOSS feature access, installed-signer update validation, dependency inventory, hosted build/test CI and development artifacts | Security rejection fixtures and hosted builds passed. [Audit](audit/README.md) still records binary/source/license blockers. Public notarized releases and updates remain open. |
| App Lock / Focus shields | System/password authentication, session shields, relocking, privacy shortcut and configuration | [App Lock](app-lock.md): policy/auth fixtures and isolated panel tests passed. Camera auth, launch prevention and complete live permission/activation verification remain open. |
| Dock / windows | Presets and shortcuts, stable window cycling, preview/switcher layouts and keys, click actions, guarded auto-quit, quit protection and maximize | [Window controls](window-controls.md): isolated policies and build integration passed. Context menus, hinge animation, display locking, live thumbnails and native interaction checks remain open. |
| Keyboard / mouse | Opt-in keyboard debounce with per-key overrides, extra-click filter and focus follows mouse | [Keyboard](keyboard-debounce.md), [click filter](mouse-click-filter.md), [hover focus](focus-follows-mouse.md): isolated fixtures passed; no physical input was injected overnight. Native permission, typing, drag, double-click, menu, Spaces and device checks remain open. |
| Clipboard | Picker, clearing, URL cleanup and Finder cut/paste | [Clipboard tools](clipboard-tools.md): policy fixtures passed. Native paste/Finder/permission interaction checks remain open. |
| Installer / archive | Signed-app DMG staging/install/backup path and archive settings UI | [DMG installer](dmg-installer.md): generated signed-app DMG fixture passed. Default-handler permissions and interactive failure recovery remain open. One earlier hosted fixture attach failed transiently; a later run passed. Retry-branch execution was not demonstrated. |
| Media | Native image/PDF/audio/video processing, local OCR and screenshot text monitoring | [Media tools](media-tools.md): generated image/PDF/OCR/silent audio fixtures passed. Live screenshot selection, video codecs, Circle to Search and automatic clipboard optimization remain open. |

The final local checkpoint passed all 13 configured CI test scripts, the separate
App Protection panel-only fixture, and a full app build with signature checks.
The phone protocol suite includes 126 checks and independent Java compatibility
checks. No messages, calls or third-party contacts were used for tests.

The locked Mac session prevented trustworthy full foreground-activation testing;
it was not unlocked. Panel-only checks do not prove activation enforcement or
physical display hotplug. Existing compiler warnings remain; this is not a
completed Swift 6 migration. Local ZIPs are development builds, not notarized
public releases.

The final local development ZIP is `build/Sapphire-local.zip` (source checkpoint
`bc1fcbc`, built before the documentation commit). SHA-256:
`fd48db926c6751f1ea5f314a45eef7d88980c8b7be3adccd1ebff9119a270c57`.
Its input inventory is `build/dependency-inventory.json`. Both are ignored local
outputs; this checksum identifies that ZIP and is not a reproducibility or
provenance audit. Hosted CI for `51785fa` passed; the later focus checkpoint's
[hosted run](https://github.com/ezariago/sapphire-foss/actions/runs/40041328603)
passed its test steps and was still building at the last pre-cutoff check. Its
final build/artifact outcome remains unverified.

## Next work

Continue the unchecked [README roadmap](../README.md), starting with the remaining
parts of existing implementations. Native interaction verification needs an
attended unlocked session and, where applicable, permission or biometric approval.
Do not mark those checks complete from isolated fixtures alone.

Actionable source work still includes general mouse controls, Super Key, snippets
and emoji; the remaining Dock and media paths above; storage/workspace/widget UI;
adapter-power and menu-bar automation; surround-audio UI; sports/finance providers;
Intelligence/Blip and Smart Inbox; and real camera/microphone/File Provider/Finder
Sync extensions. Missing third-party source, model rights, signing credentials
and human permission approvals must be recorded as blockers instead of guessed.

Android still needs SMS/calls, bulk transfer/storage and file clipboard, streaming
and extended display, widgets/handoff/universal input/Focus/relay and earbud paths.
The companion checkout is preserved at `67edf0d`; no later Android code change was
made by these Mac feature checkpoints. Existing phone implementations and their
limits are documented in [phone reconstruction](../PHONE-RECONSTRUCTION.md).

Physical Mac sleep/lid-close, radio recovery, hotspot internet-through-Mac and
third-party/OEM notification checks remain explicitly pending. Do not run
unattended hardware sleep tests or send real messages/calls to verify them.
