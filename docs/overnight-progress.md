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


Replaced the empty Space Map compatibility model with bounded direct-entry
snapshots and a selectable allocated-byte treemap in the storage workspace.
Stable sorting, grouped remainders, zero/unknown sizes and scope-vs-volume labels
keep the chart's meaning explicit. Selection uses the existing inspection,
folder/reveal and reviewed Trash row; nothing is removed by selecting a tile.
The actual storage fixture now compiles the real Space Map and tests bounded
identity/grouping/extreme-size accounting plus area/proportion/non-overlap/finite
layout invariants. Scanner/refusal regressions passed. An offscreen render of
the actual Space Map tab was visually reviewed. Final full app/signature/ZIP
verification passed (`build/storage-space-map-final-build.log`). Actual pointer/
keyboard/accessibility/TCC/recovery interactions, tree/pie and history workflows
remain open in [storage notes](storage-workspace.md).


Added the authenticated SMS/dialer draft bridge and Mac controls. Updated Android
source advertises support and requires phone-side opt-in, private notification
review and a final system composer/dialer action. In-memory drafts have bounded
IDs, immutable review tokens, expiry and disconnect/disable/replacement guards.
No SMS/call/contacts permission or actual sending/calling is introduced.

All 23 configured Mac regression scripts passed (`build/resumed-full-regression.log`),
including 144 phone protocol checks. Final Mac app/signature/ZIP verification
passed (`build/phone-action-mac-final-build.log`). Android JVM policy tests and
app/helper builds passed. A separate permission-free fixture APK verified actual
Android intent construction and crypto/framing on the USB Samsung without
launching external activities, reading user/companion data or replacing the
normal companion. It was removed afterward and the phone was verified Dozing.
Native encrypted request/reply, notification/review/lockscreen and actual composer/
dialer presentation remain open; the normal companion update is not installed by
those isolated tests. Full SMS inbox/call synchronization is not complete.
See [draft evidence](phone-action-drafts.md). Hosted CI also confirmed shortcut
lifecycle checkpoint `2c66969` successful. The intermediate clipboard-only hosted
run `fabd1f0` was cancelled while pending, not a passing hosted run.


Exposed completed scan history by folder/mode and the existing cleanup candidate
engine in Storage. History separates recorded accounted bytes from bytes moved
to Trash and never treats legacy spaceFreed as recovered disk capacity. Review
uses guarded per-item actions, inspection-only existing Trash, and the dedicated
duplicate-group review instead of a nonexistent flat duplicate candidate list.
No model isAutomatic flag triggers deletion. Real fixtures verify scope/mode
history isolation and candidate invariants. Offscreen History/Review workspace
renders were visually reviewed. Full app/signature/ZIP checks passed
(`build/storage-review-history-build.log`). Native interaction/Trash recovery,
permissions and remaining tree/pie views are still open.

Companion debug lint exposed existing Bluetooth permission and API-28 compatibility
gaps. Source now checks permission at transport boundaries, catches denial at the
actual native calls, invalidates transient session/draft state and keeps saved
pairing. Callback/advertisement identity and generation guards reject stale work.
Failed writes stop frame processing; unrelated-peer response failures do not
retire the active peer. All app/helper/isolated-fixture debug lint tasks, JVM tests
and app/helper builds passed without adding lint suppressions. Existing warnings
remain. No phone permission/radio/notification setting was changed; native denial/
regrant recovery remains unverified. Companion source checkpoint is separate
from its installed phone app. See its VERIFICATION.md for scope.


Implemented one-file Mac-to-phone transfer (up to 5 MiB) over the existing encrypted
BLE session, including the active-peer Continuity single-file bridge. Serial
bounded source preparation rejects final symlinks/special files/oversize and
detected changes. Chunk acknowledgements enforce exact sequence/counters and
phase/total deadlines. Android streams to private staging, verifies size/SHA-256
and publishes content/metadata together. Explicit phone Save verifies copied
bytes and preserves staging until confirmed Discard; no remote path, broad
storage permission, auto-open or automatic Downloads write is introduced.

All 24 configured Mac scripts passed (`build/file-transfer-full-regression.log`),
then expanded exact-limit/deadline fixtures passed separately. Android's 24 JVM
cases passed, including exact 5 MiB reception and verified-copy failures. The
separate USB fixture consumed Mac-generated packets and reconstructed/published/
verified-copied 4,097 exact synthetic bytes in its own package. It did not launch
external apps or touch normal companion/user data, was removed afterward, and
the phone was verified Dozing. App/helper builds and debug lint passed. Final Mac
app/signature/ZIP verification passed (`build/phone-file-transfer-final-build.log`).
The normal companion was not updated by isolated testing. Live BLE/Save/File Shelf/
OEM interaction remains open; Wi-Fi/bulk, reverse transfer, phone browsing and
file/image clipboard are not implemented. See [file evidence](phone-file-transfer.md).

Implemented the public Smart Inbox notification path around the previously inert
models: conservative context-based code detection, selected carrier reference
formats, bounded in-memory expiry/replay handling, Settings actions and notch
integration. Copied items are marked concealed and guarded by expiry, lock state,
configuration generation and clipboard revision. Revealing a code resets when a
new event arrives; consumed codes suppress another popover under a new event ID.
References remain explicitly Unverified; carrier buttons open landing pages
without submitting identifiers. Mail scanning is disabled in the public Settings
and carrier status/Amazon integration remain unfinished.

All 25 configured Mac regression scripts passed
(`build/smart-inbox-full-regression.log`). Expanded production-monitor fixtures
also passed after review, including lock-state rejection and clearing, stale
queued writes and duplicate-code presentation suppression
(`build/smart-inbox-tests.log`). They use injected inputs and a private named
pasteboard, without accessing user notifications, Mail, the general clipboard or
network. Full local app/signature/ZIP verification is recorded in
`build/smart-inbox-verified-build.log`. Native permission, actual notification/
phone mirroring, browser and notch interaction checks remain pending. See
[Smart Inbox evidence and limits](smart-inbox.md). The companion source remains
unchanged from the verified file-transfer checkpoint and its normal phone app
was not updated.

Resumed after the user's next usage reset. Added opt-in macOS Selection Services
for selected-text cleanup and selected-URL tracking removal. The handler uses
only the private Services selection board, bounds inputs/custom parameters,
rejects marked/multiple/invalid selections and rechecks configuration/revision.
It shares the existing sanitizer and URL policy; the global clipboard and native
paste shortcut remain separate. The public generated Info.plist now advertises
implemented selectors instead of the photo/scanning Services with empty handlers;
the upstream plist remains unchanged for private builds.

All 26 configured Mac regression scripts passed
(`build/selection-services-full-regression.log`). Real selectors and named-board
fixtures cover cleanup, Unicode/size/marker refusals, URL encoding/signature
preservation and stale configuration/revision rejection. Final local app,
signature and ZIP checks are recorded in `build/selection-services-final-build.log`.
Native Services discovery/enabling, menu delivery and third-party editor style/
replacement remain unverified. No user selection, Services registry, global
clipboard or phone setting was changed by these fixtures. Details:
[Selection Services](selection-services.md).

Implemented display scoping for Sapphire Dock previews and custom click actions
using the existing persisted display identities. Missing/ambiguous selections
fail closed. Relevant settings/topology/suspension changes invalidate queued
interaction generations and dismiss previews. Picker geometry now fits smaller
usable display areas. Native Dock placement, window switcher and preset
application are intentionally independent; the UI names that scope explicitly.

All 27 configured regression scripts passed (`build/dock-display-full-regression.log`),
then the expanded scope script also passed its production native-adapter check
using fake settings and real read-only display/session adapters. Policy fixtures
cover identity ambiguity, disconnect/reconnect, settings/suspension generations,
invalid geometry and small-screen placement. No input monitor, native Dock action,
real preference write, physical sleep or lid-close test ran. Full app/signature/ZIP
verification passed (`build/dock-display-build.log`). Real hot-plug, pointer/AX,
permission and multi-display visual checks remain open. See
[display scoping](dock-display-scope.md).

Implemented the opt-in public hinge manager as a bounded frozen-snapshot dim/blur
effect, with explicit status and limitations in Settings/README. It requires one
built-in display, a supported reporting sensor, Screen Recording and an unlocked
console session. A fresh post-interruption sensor tick and open-lid reading arm
one gesture; captures have a two-second acceptance deadline and effects a
four-second total limit. Configuration/clock/sensor/session/display failures
clear the image and invalidate capture tickets. A single outstanding native
request is retained until return even if cancellation is ignored.

Production policy/async-engine fixtures passed for freshness, arming/deadlines,
invalid configuration/readings, failure gates, stale/cancelled/oversized results,
restart, bounded capture concurrency and reentrant sensor callbacks. A separate
fake-settings/sensor fixture compiled the actual native manager/renderer and
verified disabled/invalid startup and teardown without desktop capture or panels.
Dock display regressions also passed. Full local app/signature/ZIP verification
passed (`build/hinge-animation-final-build.log`). A separate bounded hardware
probe found the Mac14,2 standard lid sensor and read one valid native report,
then released its client (`build/hinge-hardware-sample.log`). It did not move the
lid, sleep the Mac, capture the desktop or change power settings. Native capture,
visual/permission/Spaces/input behaviour and physical lid/sleep checks remain
open. See [hinge evidence and limits](hinge-animation.md).

Added independent opt-in remapping for middle/side clicks to enabled foreground
app menu commands, with configuration for standard navigation/edit/window actions,
keyboard alternates and a reserved mouse modifier. Unsupported saved actions keep
native input. The path posts no keys and reads no clipboard/selection text.
Mapped gestures preserve consumed pairs, cancel drag/long-hold actions and reject
old requests after configuration, focus, session or tap changes. New user input
cancels pending delivery; one main-queue/AX lookup is outstanding at a time, with
bounded traversal and final expiry/context checks. Remapped Close Window is skipped
where Sapphire's keyboard close protection applies.

Production policy, real unposted CGEvent, asynchronous single-flight and native
manager lifecycle fixtures passed (`build/mouse-button-tests.log`); native manager
tests use fake settings and inert hooks and invoke no real menus. Click-filter,
wheel and quit-protection regressions also passed (`build/mouse-button-regression.log`).
Full app/signature/ZIP checks passed (`build/mouse-button-final-build.log`). No test
posted input or changed documents/clipboard. Native hardware/driver numbering,
Accessibility, app menu/keyboard-layout compatibility and physical transitions
remain pending. Pointer acceleration, system button actions and smooth scrolling
are still unimplemented. README and [button details](mouse-buttons.md) record the
supported subset and its limits.

Added Storage Tree/Pie tabs. The tree projects direct entries plus retained insights
into bounded URL-normalized ancestry, keeping labelled context and rejecting paths
beneath known symlink/package/nondirectory records. It reads no extra files on
expansion and does not claim complete recursive inventory or invent context-folder
sizes/actions. The pie uses primary scoped allocation totals, with finite relative
weights, overflow-safe display totals and category-filter navigation. Existing
reviewed filesystem actions are reused.

Expanded real storage fixtures passed, including URL-directory canonicalization,
search/category/context/bounds/ancestry and pie proportion/overflow checks. Actual
workspace Tree/Pie and a multi-category synthetic pie render were visually reviewed
in offscreen fixture windows. No user folder was scanned or file trashed. Full
app/signature/ZIP verification passed (`build/storage-visualization-build.log`).
README and storage documentation describe retained-record limits and pending native
input/accessibility/TCC/Trash checks. ADB was disconnected during the checkpoint;
the user said they would reconnect it. Mac-only work continues meanwhile.

Closed the live BLE staging gap for the existing one-file sender/receiver. Added
fixed-byte local diagnostic commands and a headless mode that does not open
Settings or begin/approve pairing. A debug-only Android fixture refuses existing
active/staged files, journals/restores only the Files preference, and verifies/
discards only an exact expected transfer ID/name/size/hash match. No arbitrary
source file command or external document-provider action is exposed.

The Samsung's installed 0.3.0 companion was updated in place to the built 0.5.0
APK after signing-certificate comparison. Pairing was retained. The actual Mac
app and phone securely reconnected and passed disabled-offer rejection, fixed
4,097-byte encrypted BLE staging, independent phone byte/SHA-256 verification and
owned discard (`build/phone-file-live-device.log`). Preferences were restored;
Mac diagnostics and temporary state were removed; normal Sapphire startup was
restored; phone verified Dozing/mStayOn=false. No user file, real message/call,
browser or document picker was used. Native Save/File Shelf/OEM/maximum-size
throughput checks remain pending.

Mac full build/signature/ZIP checks passed (`build/phone-file-live-headless-build.log`).
Android debug/release builds, debug lint and 24 JVM cases passed. Release manifest
excludes the file fixture. All 29 configured Mac shell tests passed
(`build/resumed-reset-full-regression.log`); separate fake-transport harness cases
also passed for blocked setup, verification/restoration failure, exact UUID-case
cleanup and sleep attempts (`build/phone-file-live-harness-tests.log`). Both
READMEs/verification notes distinguish this native proof from full file parity.


The optional screen-off file-staging probe detected a wake and correctly rejected
its background-transfer assertion. Cleanup preserved exact UUID case, discarded
only the owned completed staging, restored the Files preference and verified
Dozing again. Cause was not attributed; asleep/locked/OEM checks remain pending.
The harness now validates sleep/last-wake observations and its four isolated fake
cases cover wake rejection as well as setup/verification/restoration failure.
Further device checks were suspended at the user's request/context; the user
explicitly retained display sleep at the usage threshold. Only Mac diagnostic
cleanup and normal app restart followed; no further phone interactions occur
until that threshold or later user direction.

Usage reached 4% remaining; implementation stopped at the requested threshold.
A final hosted-CI check exposed a Swift compiler timeout in the pre-existing
Space Map tile expression, despite passing local tests. The tile control,
formatted accessibility/help text and geometry now use separate typed helpers.
The focused real storage fixture/render passed (`build/storage-ci-typecheck-fix.log`).
The final full build was still running and the hosted rerun pending at this
checkpoint; neither is claimed passed yet. Other latest local evidence remains
29 shell scripts, four fake live-harness cases, full Mac/Android builds and the
scoped live BLE proof above. Remaining README work is not complete.

Final closure: the full local app/signature/ZIP build for the Space Map compiler
fix passed (`build/storage-ci-typecheck-build.log`). The hosted rerun is still
pending, so current hosted success is not claimed. The fix checkpoint was pushed,
KEYCODE_SLEEP was sent as explicitly confirmed for the threshold, and wakefulness
was observed Dozing with mStayOn=false. No call action or persistent
wake/notification setting was changed. The continuation automation remains PAUSED;
no more implementation proceeds after the under-5% threshold.

Resumed after another explicit usage reset and renewed phone-test authorization.
Latest hosted logs show that the previous Space Map split cleared that expression,
but the compiler then timed out on equivalent overloaded formatting in the pie
view. Pie segment/legend controls and retained-tree rows now use smaller typed
helpers with precomputed display strings. Focused real storage fixtures and
Tree/multicolor Pie renders passed locally (`build/storage-pie-ci-fix.log` and
`build/storage-tree-ci-fix.log`). Hosted verification remains separate from local
success; the new run will be inspected before claiming a green pipeline.

Native phone provider-save checkpoint: production ContentResolver Save passed
with a private debug destination, exact 4,097-byte/hash verification and retained
staging. Refused output preserves staging. Six isolated harness scenarios passed;
Android JVM, debug/release builds and lint passed. README records picker/third-party
provider/File Shelf gaps. Phone verified Dozing after cleanup; no personal files
or messages used. Account remaining: 90% primary, 38% weekly.

Region text search now replaces the Circle to Search result placeholder with an
opt-in local OCR/review/explicit Google text-search path. Native compilation and
generated-image Vision/private-temp cleanup tests passed, as did the full local
Mac compile. Visual/image search and actual picker/notch/browser checks remain
open. User steered ongoing work toward automatic clipboard sync and copied-link
prompts; those are the next priority.

Hosted repair run 40107077304 passed all configured checks, full Mac build and
artifact upload. Automatic clipboard/copy-link work now has public code: Android
foreground sends, optional Shizuku background broker, marked Mac clipboard
delivery, expiring Android notifications and a five-second compact notch prompt.
Policy, isolated pasteboard and full builds pass; native background probe was
blocked before setup by phone lock. Pending fixture activities were cleared and
phone returned to sleep. User unlock/setup choice is pending; native success is
not claimed. README and docs/clipboard-link-handoff.md record these limits.

Final copied-link checkpoint: latest full local Mac build/signature/ZIP completed
successfully; Companion/Helper builds and 26 JVM cases pass. Production Android
notification-only fixture verified private review notification and expiry by six
seconds; no clipboard access/browser opening. Latest APKs installed in place.
Background capture still awaits human unlock, and helper sending remains opt-in.
The phone was verified Dozing after tests; no persistent wake/alarm setting changed.

Attended continuation: user unlocked the phone and instructed that no further
phone screen-off action be sent, superseding the earlier threshold/test sleep
instruction. Standalone background helper read and restoration now pass. Fixed
its launcher to use separate tasks so Android cannot reuse the begin window for
restore. Live relay/filtering/notch expiry now pass with Launcher in front and
both Sapphire activities unfocused. Helper opt-out/re-enable recovered after a
bounded automatic retry with no clipboard replay; a fresh later copy passed.
Normal clipboard/Helper switches are enabled, receive-links already enabled.
Opaque phone clipboard/configuration snapshots were restored for owned runs;
Mac used only its private fixture pasteboard and returned to normal startup.
Full Mac build and Companion/Helper debug/release builds, lint and 26 JVM cases
pass. README reflects verified scope; visual/browser clicks and OEM/reboot tests
remain open. Current source adds only fixed fixture diagnostic commands and
whitelisted booleans, never arbitrary clipboard input or pairing approval.
