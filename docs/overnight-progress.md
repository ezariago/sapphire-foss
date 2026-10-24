# Overnight implementation checkpoint — 2026-10-24

The user authorized committing/pushing existing Mac and Android work, then
implementing the README's unfinished features sequentially with autonomous
decisions. They also authorized ADB use and requested phone sleep at completion
or below 5% account usage remaining.

## Preserved and pushed

- Mac: `c0c2c11` — prior continuity, notification, media/handoff verification and
  stable signing work.
- Android: `67edf0d` — prior companion media/handoff, notifications and UI work.
- Mac: `56a20e7` — FOSS feature access, real update signature/signer validation,
  fork updater endpoint, dependency inventory and build/test CI.
- Mac: `2760219` — App Lock/Focus shields, Dock presets and initial native window
  controls. Both hosted CI runs for these two implementation commits passed and
  uploaded development app artifacts. This is not a notarized public release.

Mac `dfd7c61` contains clipboard enhancements, the real DMG installer,
native compression/OCR and opt-in screenshot text capture/monitoring. Their
implementation/limits are in the feature documents linked from README. Its hosted
CI run also passed and uploaded development artifacts.

The next checkpoint hardens App Lock against stale authentication after rapid
configuration changes, relocks on deliberate app switches, ignores accessory
authentication agents and uses monotonic retry cooldowns. Privacy/Focus panels
recreate their geometry when the display layout changes. Isolated fixtures cover
these transitions; real monitor hot-plug and human authentication remain pending.
The Mac was locked at this checkpoint, so the real activation rerun could not
acquire focus from loginwindow. A separate explicit-shield mode passed panel
creation, simulated display-layout changes and teardown behind the lock screen.
No unlock or physical sleep test was attempted. Authentication lifecycle fixtures
and the full local build/signature verification passed after the final changes
(`build/app-lock-lifecycle-build.log`). The companion checkout remains clean.

## Verification so far

All eight scripts passed locally: `test-foundation.sh`,
`test-phone-reconstruction.sh` (126 protocol/Java crypto checks),
`test-app-lock.sh`, `test-dock-layouts.sh`, `test-quit-protection.sh`,
`test-clipboard-tools.sh`, `test-dmg-installer.sh`, `test-media-tools.sh`.
The separate GUI `test-app-protection.sh` passed real temporary-app activation,
shield display, unblock/reblock and teardown. Full local app builds and signature
checks passed for each checkpoint; logs/artifacts are under ignored `build/`.

Do not count provider fixtures or successful compilation as manual permission,
Touch ID, native keyboard/mouse, Spotlight, video-codec, third-party app or physical
sleep/lid-close evidence. The README remains unchecked where work is incomplete.

## Continuation

A bounded heartbeat in this chat is active until 07:00 Asia/Jakarta on
2026-10-24, every 30 minutes, named **Sapphire overnight implementation**. Honor
subsequent user steering/cancellation. It must stop on less than 5% remaining in
either account usage window, actual roadmap completion or the morning cutoff.
Do not create duplicate schedules. A bounded `caffeinate -i` process keeps the Mac
from idle sleep until 07:00 without preventing display sleep; runtime metadata
is in `build/overnight-runtime.json`.

The phone, ADB serial `RRCX102WVCZ`, received `KEYCODE_SLEEP`; Android reported
Dozing with stay-on disabled. No persistent wake/notification/alarm settings were
changed. Avoid waking the phone for Mac-only work and return it to sleep after
necessary fixture tests. Do not put the Mac to sleep unattended or contact third
parties with actual calls/messages for verification.

Prioritize completing the native implementations already added before expanding
surface area. Mouse/keyboard/snippets/emoji managers, Circle to Search, storage
surfaces, audio views, sports/finance, Intelligence/Inbox, extensions and most
Android bulk/streaming parity still require implementation. Source/license
provenance and public signed/notarized distribution have external blockers;
record those honestly and progress on another actionable item.

## Privacy shortcut checkpoint

Implemented App Lock's ⌘⌥S privacy shortcut and a matching Settings button. The
operation relocks first, invalidates pending authentication, and requests hiding
protected regular apps while excluding Sapphire and essential system apps. It
does not quit apps or dismiss a shield in front of protected content. The shared
shortcut dispatcher reports registration conflicts. Settings text now describes
these semantics instead of promising an unconditional overlay dismissal.

Injected tests verify target exclusion, disabled/no-op cases, relock-before-hide
ordering and stale authentication rejection during the privacy action. Real
shortcut routing and third-party hide/refusal behavior require an unlocked Mac
and remain pending; no personal apps or phone interactions were tested.

`./scripts/test-app-lock.sh` passed with the expanded privacy-action fixtures.
The full local app build and signature checks passed; log:
`build/app-lock-panic-build.log`. The Android checkout remains clean and the
phone still reports Dozing with stay-on disabled.

## Dock cycling checkpoint

Continuing the existing window-controls implementation: Dock cycle now chooses
the next window after the focused one and preserves a stable ring when AX puts
the newly focused window first. Closed windows leave the ring and new windows
join it. AX element identities replace index/title-based picker IDs. Thumbnail
association declines ambiguous title/geometry matches. Delayed Dock actions
recheck current app focus, feature enablement, app exclusions and chosen action;
unknown action strings no longer fall through to minimizing every window.

The new isolated `test-window-cycling.sh` checks cycle state and thumbnail record
matching and is wired into CI. Real native Dock/AX interactions remain blocked by
the locked session and human permission checks, so the README item stays open.
App Lock camera authentication still needs trustworthy identity-model/source
provenance; process-launch prevention cannot be claimed from session shields.
Those blockers are not bypassed by adding another visible setting.

Hosted CI for `01371e2` passed all configured tests and the full app build, and
uploaded development artifacts. The intermediate `241739b` run was superseded
by that push and cancelled by the configured concurrency rule.

The cycle/thumbnail policy tests and full local build/signature checks passed
after the final changes (`build/window-cycling-build.log`). The phone remains
Dozing with stay-on disabled; the Android checkout is clean.

## Dock preset shortcut checkpoint

Implemented per-preset shortcut recording/clearing and shared dispatcher
registration, with conflict/unsupported-key feedback. Actions resolve current
settings and reject disabled, deleted or reassigned bindings. Preset persistence
retains shortcuts; imports clear them and keep IDs distinct from existing local
presets. Bare/Shift-only typing keys are rejected. Expanded isolated tests cover
these format, import and stale-action cases without touching the real Dock.
Global key routing and actual Dock application remain manual verification work.

The expanded Dock tests and full local app build/signature verification passed
(`build/dock-shortcuts-build.log`). No real Dock preferences were changed. The
Android checkout is clean and the phone remains Dozing with stay-on disabled.

## Window preview presentation checkpoint

Implemented grid/list/carousel presentation for Dock previews and the window
switcher, compact title lists above six windows, larger snapshot thumbnails,
and hover/middle-click/Option-click preview triggers. Dock settings now expose
these controls. The custom Dock-click action excludes the preview's Option-click
gesture, while native Dock click behavior is preserved. Selection scrolls into
view, including the initial reverse-selection case. The switcher description
no longer advertises unsupported arrow/Q/W keyboard commands.

This checkpoint is UI/monitor implementation with full-build verification;
native input, visual layout, permission changes and multi-display behavior still
require an unlocked session. No screenshots, actual input, or personal app
window actions were performed for these changes. Live thumbnail refresh, Dock
locking, context-menu services and hinge animation remain open.

The final full local app build and signature checks passed
(`build/window-preview-layouts-build.log`). The companion checkout remains clean
and the phone still reports Dozing with stay-on disabled.

## Window switcher input checkpoint

Implemented arrow navigation, Return activation and selected-window W / normal
app-quit Q actions in the existing switcher. Q/W dismiss the picker and preserve
native save-dialog handling; essential system apps and Sapphire are excluded
from Q. The event tap uses a pure locked policy and schedules AX/UI work in
main-queue FIFO order. Epoch checks discard stale actions after configuration
changes or tap resets. Consumed command repeats/key-up events do not leak into
the newly selected app; missing modifier releases cancel safely and pass ordinary
typing through instead of interpreting it as a window command.

Expanded isolated policy tests cover these transitions without sending real
input or closing/quitting apps. Native keyboard behavior, AX close/quit dialogs,
interaction with quit protection, Spaces and permission changes remain pending.

Several expensive hosted builds were superseded before completing during the
30-minute implementation cadence. CI now queues the latest run instead of
cancelling the active run on every push, allowing complete verification to
finish. A queued/successful local build is not recorded as a successful hosted
run; hosted conclusions still require checking the actual run.

The expanded switcher/cycling policy fixtures and final full local app build
with signature verification passed (`build/window-switcher-input-build.log`).
The Android checkout remains clean and the phone remains Dozing; no personal
window actions or device input were used for validation.

## Auto-quit observation checkpoint

Hardened the existing auto-quit path: monotonic grace periods, interrupted AX
query sequences, window reopenings, exclusions, reusable PIDs and lifecycle
resets now have an isolated policy. A failed/denied window query clears the
pending deadline. State uses process launch time and skips apps whose lifetime
cannot be identified. Termination is requested once per observed empty episode;
there is no force-quit fallback. Current enablement/exclusions/trust are checked
again immediately before requesting termination.

New isolated auto-quit fixtures cover these transitions without quitting apps,
and are included in CI. Real save dialogs, native permission/lifecycle behavior
and app compatibility remain pending. Hosted CI for `a4820d1` and `8c85559` is
confirmed successful; `5fc9be7` was still running when this checkpoint started.

The auto-quit policy fixtures and final full local app build/signature checks
passed (`build/auto-quit-observation-build.log`). No real app termination was
tested. The Android checkout is clean and the phone remains Dozing with stay-on
disabled.

## Keyboard debounce and fixture reliability checkpoint

Replaced the keyboard-debounce manager and Mouse settings placeholders with a
real opt-in event filter, global timing and per-key override UI. Isolated policy
fixtures cover chatter pairs/bursts, native-repeat handling, duplicate downs,
modifier changes, independent keys, zero overrides and resets. Actual hardware,
input-method and shortcut interactions remain pending; no input was injected.
Other mouse/snippet/emoji managers remain placeholders.

Hosted `5fc9be7` succeeded. `a4fe176` failed before its new auto-quit tests ran:
hdiutil temporarily refused attaching the generated DMG fixture. The harness now
retries only that classified attach error, at most three times, with cleanup
restricted to the exact fixture image's devices. It never retries arbitrary
assertion/install failures. Product mount behavior remains unchanged. A fresh
hosted run is still required to verify CI recovery.

The keyboard policy fixtures, fresh real-DMG fixture run and final full local
app build/signature verification passed (`build/keyboard-debounce-build.log`,
`build/dmg-fixture-retry-test.log`). The local DMG run did not reproduce the
transient attach error. No physical keyboard or phone input was performed.

## Mouse click-filter checkpoint

Implemented the extra-click filter with same-button/time/position/modifier
matching, paired release suppression, accepted-drag preservation and foreground
app exclusions. Mouse settings expose the interval and application picker. No
pointer events are synthesized and native click-count metadata is preserved.
Isolated fixtures cover chatter, geometry boundaries, drag/drop, independent
buttons/modifiers, malformed coordinates and resets. Native device behavior,
double/triple-click counts and permission/app transitions remain pending.

Hosted CI for `a0b2ad5` succeeded, including all configured tests, the full app
build and development artifacts. The prior failed DMG fixture run remains
recorded as a failure; the passing later run does not by itself prove that its
transient retry branch executed.

The mouse click-policy fixtures and final full local app build/signature checks
passed (`build/mouse-click-filter-build.log`). No real pointer/button events
were sent. The Android checkout remains clean and the phone remains Dozing.

## Focus-follows-mouse checkpoint

Implemented the existing focus-follows-mouse manager with AX window hit testing,
a configurable dwell interval, current/target app exclusions, typing/lifecycle
resets, secure-input/button/modifier pauses, and final trust/front-app/pointer
checks. Mouse settings now expose it. Dwell fixtures do not focus any real app.
Native AX, menus, multiple displays, Spaces and physical-device checks remain
pending; the locked session was not unlocked for verification.

The final scheduled overnight run started at 06:35 Jakarta. It must checkpoint
and pause the existing automation at 07:00, regardless of remaining features.
This is not a completed roadmap: source provenance, public notarized distribution,
several input/media/storage/AI/inbox/extension implementations and Android parity
remain open. Physical Mac sleep/lid-close checks remain explicitly pending.

The final full local app build and signature checks passed
(`build/hover-focus-build.log`). All 13 configured CI test scripts passed locally,
plus the separate App Protection `--panel-only` fixture
(`build/final-overnight-checks.log`). The phone protocol suite includes 126 checks
and independent Java crypto compatibility checks. These fixture results do not
replace native permission, activation or hardware verification. Build logs and
local development artifacts are ignored build outputs, not committed evidence.
Hosted CI for the preceding mouse-click checkpoint `51785fa` also succeeded:
https://github.com/ezariago/sapphire-foss/actions/runs/40038240236.

## Morning cutoff — 07:00 Asia/Jakarta, 24 October 2026

Unattended implementation stopped at the scheduled cutoff, not because the
roadmap was finished or usage ran out. The final implementation checkpoint is
`bc1fcbc`; its full local build and all 14 local test/fixture invocations passed
as described above. At the last pre-cutoff check, hosted run `40041328603` had
passed its test steps and was still building; its final result remains unverified.
No new feature work was started while waiting for that run and the cutoff.

At 07:00, ADB sent `KEYCODE_SLEEP` to serial `RRCX102WVCZ` and reported
`mWakefulness=Dozing`, `mStayOn=false`. No persistent phone settings were changed.
The existing `sapphire-overnight-implementation` automation update returned
`PAUSED`. Bounded Mac idle-sleep prevention was configured to expire at 07:00;
no physical Mac sleep or lid-close test was performed.

See [the final handoff](overnight-handoff.md) for implemented paths, evidence,
remaining source/credential/permission blockers and the unfinished roadmap.
The companion checkout remains unchanged at `67edf0d` and synchronized with its
upstream. This documentation checkpoint is pushed with the implementation.

## User-requested daytime continuation — 24 October 2026

The user explicitly requested continuation after the overnight stop. The overnight
automation remains paused; this is a direct continuation, not a renewed unattended
schedule. Hosted CI is now confirmed successful for both `bc1fcbc` and `a2603af`.
Initial account usage remaining was 80% in the five-hour window and 82% weekly.

Added opt-in discrete wheel speed/direction controls and side-specific Command-key
Hyper mapping, replacing their managers' stubs. Native gestures and modified
scroll are bypassed by wheel customization. Hyper adds flags to original events
without posting input or retaining a held-key latch. Separate Super Key and shared
mouse exclusions are configurable. No persistent input/system preference changes
or physical phone input were performed. Caps Lock, pointer acceleration, button
remapping and smooth/linear scroll remain open.

The wheel and Super Key fixtures passed using pure policies and unposted
CGEvent objects, including their wheel-modifier interaction. A fixture assertion
initially assumed a keyboard-only field could be set on every mouse event type;
it was corrected to compare the actual pre-transform field value. No production
failure was masked by that change. Full app build and native interaction evidence
are recorded separately after verification completes.

The final full local app build and signature verification passed for the wheel
and Super Key implementations (`build/mouse-super-key-build.log`). Both new test
scripts are included in CI. Actual wheel/keyboard and permission transitions
remain pending as documented in [wheel controls](mouse-wheel.md) and
[Super Key](super-key.md); no native input behavior is claimed from the build.

Text snippets now have a public manager, matching/placeholder policies and
guarded AX edit transactions. Pending work requires a matching eligible press
and release in the same foreground process and is invalidated by subsequent
input, focus/lifecycle or configuration changes. Return/Tab never trigger it.
Existing settings descriptions now identify supported AX fields rather than
claiming every app is supported. Delimiters, UTF-16 boundaries, input tickets,
refused writes and concurrent edits have fixtures. Date/time and lazy clipboard
placeholders are bounded and do not recursively interpret inserted content.

The isolated policy/transaction fixtures and full app build/signature checks
passed (`build/snippets-final-build.log`). A separate real AX background-fixture
test passed selected-range/text replacement and native secure-field subrole
discovery (`build/snippets-native-test.log`). It did not focus a user app, inject
typing or access the user's clipboard. Global key routing, real secure-field
enforcement, input methods, undo and third-party editor compatibility remain open.
See [text snippet evidence](text-snippets.md).

Replaced the Emoji settings/manager placeholders with an opt-in macOS Emoji &
Symbols action, configurable shared-dispatcher shortcut, stale-configuration
guards, conflict reporting and app exclusions. macOS owns search, skin tone and
insertion; colon-triggered suggestions remain unimplemented. The full local app
build and signature checks passed (`build/emoji-picker-build.log`). The picker was
not opened automatically over user content and actual presentation/insertion and
OS shortcut coexistence remain manual checks. See [picker notes](emoji-picker.md).

Implemented the storage workspace, notch widget and detail view using the public
scanner/capacity model: scans/cancel, navigation, search/sort, categories, duplicate
paths, issues and reviewed per-item Trash requests. Notch capacity refreshes do
not scan files. Available/purgeable/free readings are distinguished. Scanner
fixtures use a unique cache folder/defaults domain and test real duplicate hashes,
filter/sort, capacity bounds, protected/out-of-scope/symlink rejection, cancellation
and stale-removal refusal. No file was trashed and no user data was scanned.

Both the ordinary fixture and optional native offscreen render passed; the
synthetic workspace render was visually reviewed. The final full app build and
signature checks passed (`build/storage-checkpoint-build.log`). Successful Trash
and recovery, TCC/folder-picker behavior and actual notch placement remain native
checks. Interactive Space Map/tree/pie and history/recommendation UI are still
incomplete. See [storage evidence](storage-workspace.md).

Hosted CI confirmed `2574bde` successful. The intermediate snippet-only run
`af15a89` was cancelled while pending when a later checkpoint replaced it; it is
not recorded as a passing hosted run. Later runs include that code and its tests.

Connected Monitoring settings to the existing readout and alert engines. Added
proper stop/restart subscription cleanup, bounded imported thresholds, fresh
sustained windows after threshold changes and generation-guarded permission/disk
callbacks. Invalid samples/clock rollback/overflow and battery/disk latch inputs
are handled without integer conversion crashes or reviving stale deliveries.
The settings accurately identify the monitored home-folder volume and GiB units.

Monitoring policy/math fixtures and a snippet regression run passed; the final
full app build/signature verification passed (`build/monitoring-final-build.log`).
No notification, sound, artificial load or disk-pressure test was performed.
Actual permission/readout/alert behavior remains on the native checklist in
[monitoring notes](monitoring.md). Compatibility initialization paths retain their
original full-build behavior; this is not a claim that unavailable private full
build dependencies have been tested. Hosted `c4b4c33` succeeded, including the
snippet code/tests from the previously cancelled pending checkpoint.

Corrected power telemetry presentation: missing/invalid sensor values are distinct
from measured zero, the System Power headline uses system load, and an unavailable
adapter reading no longer borrows that value or charger metadata. AC status uses
the battery monitor's source state and unknown source state is labelled. Replaced
the solid placeholder bar with comparative system/adapter bars and clarified the
debug menu's charger rating label.

Pure telemetry and production battery-view-model publisher fixtures passed with
injected providers, including missing/zero/invalid values and stop/restart. The
final full app build/signature checks passed (`build/power-readings-final-build.log`).
No power setting, charger or phone state was changed by these tests. Actual sensor
availability/calibration and charger/dock transitions remain hardware checks in
[power evidence](power-readings.md).

Added per-app 8D and stereo-surround controls connected to the existing public
manager/mixer, including live parameter bindings, reset and active-tap status.
Extracted the existing settings models without changing Codable keys or legacy
defaults and normalized all numeric inputs before renderer use. Parameter-only
updates now notify the UI without unnecessarily restarting capture reconciliation.

Spatial parameter/default/legacy decode/persistence fixtures passed without
starting a mixer or playing audio. Full app build/signature checks passed
(`build/spatial-audio-build.log`). Actual permission, routing, device recovery and
acoustic checks remain explicitly pending in [spatial audio notes](spatial-audio.md).


Replaced the central Keyboard Shortcuts placeholder with a searchable catalog
for clipboard, Emoji, OCR, App Lock privacy, planes, existing Snap Zone mappings
and Dock presets. It supports recording/clearing where applicable, per-action
disabling, active catalog conflict checks, stale-target-safe writes and dispatcher
mapping diagnostics. Mapping does not prove native key delivery or external OS
conflict resolution. See [shortcut evidence](keyboard-shortcuts.md).

The final full app build and signature checks passed
(`build/shortcut-catalog-final-build.log`). The combined regression run initially
found a storage fixture race: capacity is delivered independently from directory
scan completion. The fixture now awaits capacity before asserting its bounds.
All 20 configured CI test scripts passed across the initial run and resumed
storage-through-phone checks (`build/daytime-regression.log` and
`build/daytime-regression-remainder.log`). No synthetic keys, notifications,
playback, SMS or calls were used. Native shortcut recording/delivery remains open.
Hosted storage checkpoint `478e31b` succeeded; monitoring checkpoint `6eb5aed`
was cancelled while pending, and later checkpoints include its code/tests.

The current ignored development ZIP, rebuilt from the shortcut-catalog source
before this documentation/test-only checkpoint, has SHA-256
`11d5c5646f7bc89985e62382db39f27814af5d1aa903e32ec07c464162b98596`.
Its input inventory was refreshed. This is a local ad-hoc-signed development
artifact, not a public notarized release or reproducibility/provenance audit.
The overnight automation remains paused; daytime continuation was directly
requested by the user. The roadmap is still incomplete, with the native,
third-party source/credentials and substantial implementation blockers above.


Daytime stopping checkpoint, 24 October 2026: account usage reported 96% used
in the five-hour window (4% remaining) and 30% used weekly (70% remaining).
Stopped further implementation per the user's threshold. Shortcut catalog
`0c137f7` and lifecycle follow-up notes `fbc1d47` were pushed. The connected
Samsung received `KEYCODE_SLEEP` and reported `mWakefulness=Dozing`,
`mStayOn=false`. No persistent wake, notification or alarm setting was changed;
this verifies current sleep only and cannot guarantee the phone never wakes.
The overnight automation remains paused. Remaining implementation and native
checks are explicitly open; the complete README roadmap is not finished.


Resumed on the user's direct request after a usage reset and USB reconnection.
The shared dispatcher now invalidates queued work before debounced settings
rebuilds and across provider/recording/permission/event-tap transitions. Current
targets/bindings are resolved again at execution, provider collision priority is
stable, CG repeat events pass through and throttling uses monotonic uptime.
Production-dispatcher fixtures passed with inert event/action dependencies,
including deletion/reassignment, rapid disable/re-enable, provider replacement,
recording, permission, shared-tap reset and unrelated-setting preservation.
Dock regression fixtures passed. The final full app build/signature checks
passed (`build/shortcut-lifecycle-final-build.log`). No real keys/window actions
were injected. Native routing and OS conflict checks remain open. The overnight
automation remains paused; this is directly requested daytime work.


Implemented the public menu-bar profile engine for battery thresholds, actual
charging/battery power and readable Wi-Fi conditions. Async current-state reads
are opt-in, bounded by generation/freshness checks, stop/restart and simulated
sleep/wake handling. Unsupported Focus/script conditions and display/Space/Focus
bindings leave the profile inactive; no script path is executed. Settings report
these limits. Controller wiring now holds profile reveals against auto-rehide,
yields to Zen mode and rechecks on Zen exit, including clearing on disable.

Policy and production-engine fixtures passed with injected readings; no actual
Wi-Fi/power changes, scripts or physical sleep tests were used. Final full app
build/signature checks passed (`build/menu-bar-profiles-final-build.log`). Actual
menu-bar layout/gesture/Zen behavior, Location permission and charger/network
transitions remain native checks in [menu-bar profile notes](menu-bar-profiles.md).


Implemented opt-in automatic clipboard image optimization with serial bounded
ImageIO PNG encoding, orientation/alpha handling and revision/configuration guards.
Only declared PNG/TIFF image representations are captured; automatic pasteboard
conversion aliases are distinguished from the actual item's formats. Rich,
concealed, multi-item, unknown/ignored-app and secure-input cases are skipped.
App changes, sleep, screen lock, new copies and shutdown invalidate pending work.
Named-pasteboard/native image fixtures passed without touching the general
clipboard. Full app builds/signature checks passed, including the final shutdown
guard in the combined storage build (`build/storage-space-map-final-build.log`).
Actual inter-app copy/paste/history/sharing coexistence remains native work;
macOS pasteboard writes still have a documented narrow cross-client race.
See [media notes](media-tools.md).
