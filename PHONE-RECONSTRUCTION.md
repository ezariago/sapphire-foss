> Notification update (2026-10-22): the independent companion now includes opt-in
> notification mirroring. The early scope lists below describe earlier milestones;
> see [Notification mirroring](#notification-mirroring-2026-10-22) for current behavior.

> Update: an independent editable Android companion and real hotspot helper now
> live in [sapphire-android-companion](https://github.com/ezariago/sapphire-android-companion/blob/main/README.md). The local-only hotspot
> limits below describe the original Play Store APK, not the new companion.

# Phone / Android reconstruction

This is an independent replacement implementation of part of Sapphire Continuity.
It is **not the author's original Swift source**, and it does not restore every private feature.

## Evidence inspected

- Public repository: commit `792f9b4ea3d556d7566fbc38592fe54e88d89dc0`.
- User-provided `Sapphire.zip`: Mac version 3.5, build 1; universal Intel/Apple silicon executable.
- Archive SHA-256: `e8ad7fd4cdb9cafa8ef4bb98725708cd618cf99e4775bfc12488cc4270148fd4`.
- The Mac archive contains no `.swift`, `.kt`, `.java`, or Android APK files.
- The Mac executable retains protocol strings and reflection metadata, but most application function symbols are stripped.
- Installed Android companion: `com.shariq.sapphire`, version 1.0.1 (3), copied through the already-authorized USB development connection.
- Android base APK SHA-256: `be8da8acc664f53557d97af6c9095f271a8cb8052841d504f85be6184331a1e7`.
- Decompiled Android output has errors in some methods; it is reference material, not a recovered, buildable Android project.

The original apps, APK, extracted strings and decompiler output are kept under ignored `build/` paths. They are not linked into the replacement or included in its source patch. Configuration/API credentials from the reference apps are not copied into this build.

## Replacement source

| File | Responsibility |
| --- | --- |
| `Sapphire/Reconstruction/PhoneWire.swift` | Advertisements, bounded GATT message reassembly, JSON envelopes, QR payload, ECDH pairing, HKDF, authenticated BLE frames and replay rejection |
| `Sapphire/Reconstruction/PhoneBluetoothLink.swift` | Bluetooth discovery, subscription/writes, pairing state, confirmations, Keychain persistence, encrypted sessions, phone status and basic commands |
| `Sapphire/Reconstruction/PhoneSettingsView.swift` | Replacement Continuity settings and phone controls |
| `Sapphire/Stubs/ContinuityCore.swift` | Connects the replacement to existing public phone-status/media interfaces |
| `Tests/PhoneReconstruction/` | Java interoperability fixture and Swift protocol tests |

## Reconstructed protocol details

These details were checked against the installed Android app, not guessed from feature names:

- BLE service `A17E0001-4D61-6373-6170-706C696E6B00`; inbox/outbox/control use suffixes `0002`, `0003`, `0004`.
- Manufacturer ID `0xFFFF`; version/type, eight-byte SHA-256 device handle, 16-bit capabilities, battery, optional pairing flag.
- GATT chunks have a flags byte, little-endian 16-bit message ID and payload. Start/end flags are bits 0/1.
- QR content is base64-encoded JSON with `v`, `macDeviceId`, `macName`, `ecdhPublicKey`, `nonce`, `spkiSha256`.
- Pairing uses P-256 ECDH with uncompressed public points and 16-byte nonces. HKDF-SHA256 salt is Mac nonce followed by phone nonce; info strings are `sapphire-continuity-link` and `sapphire-continuity-sas`.
- The six-digit SAS uses the first four derived bytes as an unsigned big-endian integer modulo 1,000,000.
- BLE sessions derive separate directional keys from the pairing key and fresh 32-byte nonces using `sapphire.ble.mac-to-phone.v1` / `sapphire.ble.phone-to-mac.v1`.
- Encrypted frames use `SBE1`, an eight-byte big-endian counter, ciphertext and a Poly1305 tag. ChaCha20-Poly1305 authenticates the header; nonce is four zero bytes followed by the counter.
- The replay window is bounded to 256 counters. Authentication must succeed before replay state advances.
- Envelopes carry `v`, `id`, `type`, `ts`, `counter`, `payload`; optional fields are accepted with protocol defaults.

The modern BLE transport does not require a TLS certificate. This replacement leaves the required legacy `spkiSha256` QR field empty and does not advertise a Wi-Fi/TLS endpoint. It never disables TLS validation or reuses the vendor's identities.

Android reference locations under `build/ReferenceBuild/android-decompiled/sources/`:

- `Y3/k.java`: pairing key agreement, HKDF and confirmation code.
- `Y3/i.java`: crypto primitives and nonce encoding.
- `p033f4/C1476f.java`, `C1475e.java`, `C1479i.java`: BLE service, chunks and encryption.
- `com/shariq/sapphire/protocol/*$$serializer.java`: on-wire JSON field names.
- `p044h4/C1574w.java`, `O3/q.java`, `p044h4/W1.java`: QR parsing and pairing confirmation flow.

## Current scope

Implemented for device testing:

- Discover nearby Sapphire Android phones.
- Pair by scanning the Mac QR code and comparing/confirming the six digits on both devices.
- Store this replacement's pairing key in macOS Keychain under its own service name; the official app's pairing store is untouched.
- Reconnect and establish authenticated, replay-protected BLE sessions.
- Read phone battery/status, receive phone media state and send playback commands.
- Send up to 12 KB of clipboard text using an explicit button; received text is copied to the Mac only when requested.
- Mirror phone notifications with per-app muting, supported actions and replies.
- Control the phone's internet hotspot through its authorized helper.
- Share web links in either direction, with explicit opening on the receiving device.
- Recover after Android Bluetooth radio off/on without restarting the companion.

Not implemented: Wi-Fi/bulk transfer, file/storage browsing, screen mirroring, extended display, virtual camera/microphone, SMS/calls, Android widgets, image/file clipboard, full app-state handoff and universal keyboard/mouse. Their protocol identifiers may be visible in a binary, but each still requires substantial implementation and verification. No account/subscription backend is reconstructed or changed.

## Build and test

```sh
cd /Users/ezariago/Projects/Sapphire
./scripts/test-phone-reconstruction.sh
SAPPHIRE_GITHUB_SSH=1 ./scripts/build-local.sh
```

For faster device-test iterations, prefix the build command with `SAPPHIRE_FAST_BUILD=1`. This disables optimization only for the app; package dependencies stay cached. Omit it for the final optimized Release build.

The protocol tests require a JDK with ChaCha20-Poly1305 support in addition to Xcode. They test fixed public fixtures, not live pairing credentials. They compare ECDH/HKDF/SAS and encrypted frames against an independent Java/JCA implementation; test GATT sizes, malformed and expired fragments, advertisements, tamper rejection, wrong keys and replay rejection.

### Local diagnostic mode

Launch the rebuilt app with `--phone-diagnostics` to open the phone pane, reconnect a saved phone (or start pairing if none is saved) and publish diagnostic state in a process-specific, mode-0700
temporary directory. `python3 scripts/phone-diagnostics.py state` shows transport
state without scraping the UI; `pair`, `scan`, `connect <UUID>`, `disconnect` and
`quit` provide local developer controls. `qr` returns only the ephemeral public QR
challenge. There is no network listener, confirmation command or facility to read
pairing keys, notification contents or clipboard contents. Matching-code approval
stays in the normal UI. Diagnostic files have mode 0600. This mode is opt-in and is
inactive during a normal launch.

## Pairing and device verification

1. Quit other running Sapphire copies and open the rebuilt app.
2. Open Settings → Continuity (Phone / Android) → **Pair a phone**.
3. On Android, open Sapphire → Pair your Mac. When exactly one nearby phone advertises pairing mode, the Mac opens its Bluetooth transport automatically. Otherwise select the phone in the Mac's nearby-phone list, above the QR code.
4. Once the Mac says the transport is connected, choose Pair with a code on Android and scan the Mac's QR code. Accept any required Bluetooth permission/system pairing prompts yourself.
5. Compare the six-digit codes. Confirm on the Mac and phone only when they match.
6. Wait for **Connected securely over Bluetooth**. A Bluetooth connection alone does not count as authenticated success.
7. Check that battery matches the phone; play media and test pause/resume.
8. Use nonsensitive sample text to test clipboard transfer in both directions. Android restrictions may require its app to be in the foreground or the phone's explicit send-to-Mac action.
9. Disconnect/reconnect, then quit/relaunch Sapphire and confirm the saved pairing reconnects.

Pairing opens a three-minute window. An unrelated device or a different code must not be accepted. New local pairing uses a separate Mac identity named with `(Local Build)`; it does not silently replace the original app's identity. After successful pairing, the public app's Continuity setting is enabled so existing status/media interfaces can receive updates.

Compilation, protocol fixtures, UI checks and real-device checks are separate validation stages. Only the checks explicitly reported in the task's final result should be considered verified.

## Device-test findings

The first on-device attempt confirmed BLE service discovery, subscription, negotiated MTU, chunk transfer and bidirectional `hello` messages. The user confirmed the replacement settings and QR code were visible. It did **not** complete pairing.

The Android companion sends plaintext `hid.prefs` and status/media requests during its initial hello, and retries `pair.hello` while waiting for confirmation. The replacement now ignores unrelated plaintext setup messages without applying them or closing pairing, treats identical pairing hellos as retries, and ignores delayed confirmations once pairing has completed. These changes do not enable unauthenticated clipboard, commands or phone status. Tests cover the handshake allowlist and deterministic retry key agreement.

The phone can display a six-digit code as soon as it scans the QR. That alone does not prove it sent a pairing reply, that the Mac received one, or that either side has authenticated the other. The Mac code and an authenticated encrypted response are separate required milestones.

### Successful device verification

Tested with the connected Samsung Galaxy S24 Ultra (SM-S928B), Android 16,
Sapphire Android 1.0.1 (3):

- The new Mac build discovers and connects to the phone automatically when it
  advertises pairing mode; the user scanned the fresh QR and completed pairing.
- The Mac reached **Connected securely over Bluetooth**, receiving authenticated
  status and media-state replies. The user independently confirmed connection.
- Android logs confirm receipt of encrypted `clipboard.update` messages during
  the user's clipboard checks. Clipboard contents were not included in diagnostics.
- Reconnection initially exposed a stale cached-peripheral problem. Android's BLE
  address changed after advertising restarted, so reconnection now scans for the
  paired device's advertisement handle and accepts the new peripheral only as a
  transport candidate. Stored address updates require an authenticated encrypted
  frame; the saved pairing key still proves identity.
- A fresh Mac process loaded the saved Keychain pairing and reconnected securely
  without another QR scan, including across observed BLE address changes.
- A subsequent normal launch, with diagnostic mode disabled, automatically
  reconnected and continued receiving authenticated status and media replies.
- The packaged app was extracted from its ZIP, passed strict nested signature
  verification, and its executable matched the tested build byte for byte.
- All 42 protocol checks pass, including independent Java crypto fixtures,
  tamper/replay handling and rotated-address discovery.

Active playback commands and notification previews still need separate functional
checks. The unimplemented features listed above remain unavailable. The packaged
device-test build uses `SAPPHIRE_FAST_BUILD=1`; run the default build command to
produce an optimized build from the same source.


## Automatic clipboard and instant hotspot

Mac → Android text clipboard delivery now follows new pasteboard changes while
an authenticated phone is connected, without a send button. It defaults to on;
Settings → Continuity → Phone controls has an **Automatically send Mac clipboard
text to phone** toggle. Turning it off, disconnecting or reconnecting resets the
baseline, so old/offline copies are not sent later. The existing shared pasteboard
monitor detects changes (up to a one-second fallback delay), without a second
polling timer. Empty, non-text and 12,000-byte-or-larger copies are skipped.
Concealed/transient/automatically generated items, clipboard history's ignored
apps and known password managers are excluded. Copying received phone text does
not echo it back. Android's existing clipboard handler also suppresses echoes.
Android clipboard restrictions may still require its app to be foregrounded.
Phone → Mac text retains its explicit Copy action.

**Instant hotspot** requests `hotspot.request` over authenticated BLE, handles
`hotspot.status` and validates `hotspot.credentials` (SSID, passphrase, band and
WPA2 security). The Mac requests Location access when needed, scans for the exact
SSID and associates using CoreWLAN away from the UI thread. Credentials remain in
memory; they are absent from diagnostic snapshots, logs and source control.
Unsolicited credentials outside a user-started request are ignored. Timeout,
permission-denied, unsupported and stopped states have visible recovery guidance.
The disconnect action leaves only the network joined by this feature. Android
manages hotspot shutdown; this companion has no `hotspot.stop` command.

The installed Sapphire Android 1.0.1 (3) invokes
`WifiManager.startLocalOnlyHotspot`, which creates a local network **without
internet access**. Its UI says “Share your mobile connection”, but that behavior
is not implemented by this APK's hotspot handler. This Mac implementation labels
that limitation before joining. True mobile internet tethering requires changes
to the Android companion; restoring Mac source cannot add it to the existing APK.
See Android's local-only hotspot documentation:
https://developer.android.com/develop/connectivity/wifi/localonlyhotspot

To use: keep Sapphire connected over Bluetooth, enable Instant Hotspot and Nearby
Wi-Fi devices permission in the Android app, then click **Connect to phone
hotspot** on the Mac and allow macOS Location access. Joining switches your Mac's
current Wi-Fi connection. Use **Disconnect hotspot** to leave it, then choose your
normal Wi-Fi network if macOS does not reconnect automatically.

Developer mode additionally permits `hotspot`, `hotspot-leave`, `clipboard-on`
and `clipboard-off`. `hotspot-probe` requests and validates the phone’s hotspot
credentials without switching Mac Wi-Fi or requiring a Wi-Fi scan. These exercise the same user actions and do not expose
clipboard text or Wi-Fi credentials. No approval or pairing-code command exists.


### Clipboard device verification (2026-10-22)

- The Galaxy S24 Ultra received two new plain-text samples automatically, with
  one encrypted `clipboard.update` per copy and no send-button interaction.
- A concealed clipboard sample produced no transfer.
- A copy made while automatic sending was disabled was not sent when resumed;
  a subsequent new copy was delivered normally.
- Pasting into Android Settings search reproduced the second exact test sample,
  verifying the Android system clipboard rather than just message reception.
- The protocol suite now passes 58 checks, including UTF-8 clipboard limits,
  pasteboard counter resets, echo suppression and hotspot credential validation.


### Hotspot verification and packaging (2026-10-22)

The final build reconnected using the saved pairing. Its authenticated hotspot
probe caused the Galaxy S24 Ultra to receive `hotspot.request`, start the hotspot
and return valid encrypted WPA2 credentials. The probe intentionally did not
switch Mac Wi-Fi. macOS reports Location authorization as not determined, so
actual Mac Wi-Fi association remains unverified until the user allows Location
access and uses **Connect to phone hotspot**. The probe's temporary hotspot was
cleaned up by restarting the Android companion; the paired identity was retained.
A new clipboard copy was also delivered automatically by the final executable.

The ZIP was extracted, passed strict nested code-signature verification and its
executable matched the tested build byte for byte. Sapphire was relaunched in
normal mode with automatic clipboard sending enabled.


## Independent Android replacement

[sapphire-android-companion](https://github.com/ezariago/sapphire-android-companion) is the separate Android Studio/Gradle repository. Its main app
(`dev.sapphire.companion`, target SDK 36) and narrow hotspot helper
(`dev.sapphire.companion.hotspothelper`, target SDK 28) coexist with the original
Play Store package. On Android 16 the helper uses the user's authorized Shizuku
access; an old target SDK alone is insufficient. It invokes Android internet
tethering with carrier checks enabled, not `startLocalOnlyHotspot`.

The Mac scans both the legacy service and the new independent
`DAB10001-5A50-434F-4D50-414E494F4E31` service, then selects matching inbox/outbox
characteristics for that advertisement. Authentication is still required; the
service UUID itself is not a trust decision. Encrypted phone status advertises
internet-hotspot and stop support. The Mac adjusts its instructions and sends
`hotspot.stop` when leaving a supported hotspot.

The replacement has passed real-device pairing, both text clipboard directions,
hotspot start/credentials/stop with a confirmed cellular upstream, saved-key
reconnection, and an app-update recovery test. A restarted Android GATT service
can leave a stale physical BLE link alive; service-invalidation handling and
heartbeat/write-failure recovery now reopen that transport automatically.

See [the Android README](https://github.com/ezariago/sapphire-android-companion/blob/main/README.md) for build/setup/modification instructions and
[Android device verification](https://github.com/ezariago/sapphire-android-companion/blob/main/VERIFICATION.md) for the precise tested scope. Actual Mac Wi-Fi
association still requires Location approval; no network switch was performed by
the diagnostic hotspot probe.


### Notch device status (2026-10-22)

The replacement companion broadcasts changed battery/charging, mobile provider, 0–4 modem signal level and active network summaries over the encrypted Bluetooth connection. It checks every two seconds; periodic refresh requests remain supported. Carrier/signal use the public Android telephony summary APIs without runtime phone or location permission. Unknown telemetry stays unavailable rather than appearing as a fabricated signal strength.

The former empty `ContinuityNotchDetailView` now opens a live device panel with status and Instant Hotspot controls. The compact notch status shows carrier and four independently filled signal bars. Hotspot actions reuse the existing authenticated helper/CoreWLAN flow, including permission handling, busy states and disconnect.


### Mac sleep/wake recovery (2026-10-22)

The Mac observes workspace sleep/wake notifications. Sleep drops the BLE manager,
peripheral, GATT handles, session keys and queued writes, cancels pending timers,
and expires any unfinished pairing challenge. Wake creates a fresh manager after
a two-second radio recovery delay and scans for the saved phone. Transient
connection/discovery/subscription failures use the same delayed recovery.
Callbacks from retired managers are ignored. An explicit Disconnect or disabled
Continuity cancels recovery and suppresses reconnection, including during sleep.

To exercise the real handlers without putting the Mac to sleep, launch a local
build with `--phone-diagnostics`, then run:

```sh
./scripts/test-phone-lifecycle.py PID
```

The test covers repeated sleep/wake, cleared session state, explicit disconnect
while asleep and during recovery, and another sleep during the wake delay.
It leaves scanning enabled, never approves pairing and never switches Wi-Fi.
Validation: the macOS build and strict signature verification passed; the live
handler lifecycle test passed, as did all 67 protocol checks. Both Android APKs
and JVM tests passed in the separate Android checkout. Physical lid-close/radio
recovery still requires a real-device smoke test.


## Notification mirroring (2026-10-22)

The independent companion now implements Android `NotificationListenerService`.
Sharing defaults to off. In the Android companion, enable **Share phone
notifications with paired Mac**, tap **Allow notification access**, and grant
Sapphire access in Android Settings. Notification access is separate from the
permission to show the companion's own foreground notification.

The Mac Phone / Android pane includes notification controls and a list of up to
30 active notifications. New posts and updates appear in the notch. Dismissal,
app-provided buttons and free-form reply actions are sent back to Android;
replies/actions require the phone to be unlocked. macOS banners are optional and
request their own Mac permission when enabled. Existing notifications synchronize
quietly after reconnect, without replaying old alerts. Removal on either side
clears the corresponding active item; dismissing a notch alert alone only hides
that alert and leaves the phone notification active.

Only authenticated Bluetooth frames carry notification content or commands.
Disconnect, disabling mirroring or a listener reset clears Mac notification state.
No notification history is written to the reconstruction's diagnostics; those
snapshots expose only the count, whether a notch alert exists, and the state of
the fixed synthetic debug notification. Optional macOS
banners are stored by macOS Notification Center until removed. The Android side
excludes secret, ongoing, group-summary, other-user/work-profile and Sapphire
service notifications. Low-priority and Android system notifications are excluded
by default and have Mac controls. Android/OEM redaction remains in effect. Images,
attachments, notification icons and launching phone apps from a default banner
click are outside this first implementation.

### Wire behavior

- Mac sends encrypted `notif.subscribe` with `enabled`, `includeGeneral` and
  `includeSystem` after authentication and when notification preferences change.
- Android sends `notif.reset`, then up to 30 `notif.postedV2` snapshot entries;
  future posts use `snapshot: false`. Each entry has `key`, `revision`, `appId`,
  `appName`, `title`, `text`, `postTimeMs`, `clearable`, `isGeneral`, `isSystem` and
  up to four `actions` (`id`, `title`, `allowsReply`).
- `notif.removed` carries the key/revision. `notif.dismiss` and `notif.action`
  reference the same revision; action requests also carry `actionId` and optional
  `replyText`. Android rejects stale revisions and keeps PendingIntents locally.
  Authentication-required and unsupported non-text input actions are omitted.
- Commands include a unique `requestId`, echoed by `notif.actionResult` for action
  feedback. The Mac prevents concurrent submissions and times out unanswered
  requests without automatically resending a reply. Text is bounded to
  4,096 UTF-8 bytes; replies to 4,000 bytes. The BLE event queue coalesces updates,
  preserves removals, and reconnects for a fresh snapshot on capacity overflow.

### Validation

The Mac protocol suite covers notification payload limits, Unicode, duplicate
and excessive actions, duplicate events, revision updates/removals, silent
snapshots, bounded storage, disconnect clearing and plaintext rejection.
All 98 Mac protocol checks and 14 Android JVM tests pass. Android tests cover
filtering, UTF-8 truncation, post/removal ordering, reposts, action-result ordering
and queue backpressure. macOS and Android debug/release builds pass; the release
APK manifest was checked to exclude the debug fixture.
On the connected Galaxy S24 Ultra, with notification access explicitly granted
and sharing enabled, the real encrypted link passed: quiet initial synchronization,
new notification arrival, update replacement, Mac-triggered app actions, free-form
reply delivery, dismissal from Mac, removal from phone, disconnect clearing and
quiet restoration after simulated sleep/wake. The Android fixture receiver
independently confirmed the action and exact synthetic reply. The fixture was
removed after the checks. No real messages were sent.

Third-party app compatibility, notification-access revocation, locked-phone/OEM
behavior and optional macOS banners have not yet been exercised end to end.
Physical lid-close/radio recovery remains a separate test from simulated handlers.
Native UI automation became unavailable during this run; the settings window
was observed before that failure, and the later notification lifecycle/actions
were verified through production bridge/transport state and the Android receiver,
not by visually checking every notch/button state.

Debug Android builds include `NotificationFixtureActivity`, an exported test
activity that posts one fixed synthetic notification. Its non-exported receiver
handles replies/actions locally; it never messages another person. Only this
fixed, tagged fixture is exempted from the debug build's own-app filter. It is
absent from release APKs. With sharing and notification access enabled, run:

```sh
adb shell am start -n dev.sapphire.companion/.NotificationFixtureActivity
```

Verify arrival/update on Mac, **Test action**, a reply of `Sapphire reply fixture`,
and dismissal. The fixture stores only success booleans, never reply text.


With a securely connected debug companion and an unlocked phone, the automated
synthetic check can exercise arrival, update, Android action/reply delivery,
dismissal, phone removal and quiet reconnect:

```sh
python3 scripts/test-phone-notifications.py MAC_DIAGNOSTIC_PID
```

It uses the opt-in Mac diagnostic commands `notification-test-action`,
`notification-test-reply` and `notification-test-dismiss`. These only target the
fixed companion fixture and cannot take a notification key or arbitrary reply
text. The reply is always `Sapphire reply fixture`. The script removes its own
synthetic notification when finished; physical sleep and ordinary third-party
app/OEM behavior still need separate checks.


### Immediate Mac dismissal

Dismiss now removes the Mac entry, queued alert, active notch activity and optional
macOS banner immediately after queuing the phone request. It also closes an open
reply editor. The Mac does not wait for the phone's acknowledgement or removal
event. Delayed duplicates of the dismissed revision are suppressed; a genuinely
new revision may still appear. Dismissing one item does not consume the next queued
notification or close an unrelated activity.

The device script now checks the actual selected notch activity as well as the
notification list, and supports `--dismiss-only` to verify dismissal/removal
without sending replies/actions or simulating sleep. It requires an ADB-connected
phone even when the Mac/phone Bluetooth link is already secure.

Validation for this change: all 98 protocol checks and the macOS build passed.
A local harness using the production bridge and targeted activity-dismissal method
confirmed immediate closure, reply-state cleanup, next-alert preservation,
idempotent acknowledgement, duplicate suppression and unrelated-activity safety.
The updated on-device script could not run because the phone was no longer
connected to ADB; the encrypted Bluetooth connection remained available.


### Per-app notification muting (2026-10-24)

Notification cards now offer **Mute [app] on Mac** in their options menu and
right-click menu (including cards in the notch). Settings → Continuity → Phone
notifications lists muted apps with **Allow on Mac** controls, available even
while disconnected. The saved setting uses Android package IDs, so apps with
similar names are filtered independently; only the package ID and display name
are persisted, without notification content.

Muting immediately removes that app's Mac entries, queued alerts, reply editor
and optional macOS banners. Other apps keep their alerts and pending actions.
The phone's notifications remain untouched. Live events and reconnect snapshots
from muted apps are filtered on the Mac. Allowing an app again requests the
phone's current snapshot, restoring existing entries quietly when connected.
Mute preferences survive app restart and reconnect.

Validation: all 107 protocol checks pass. The production bridge/dismissal harness
also passes selective removal, next-alert preservation, composer cleanup,
pending-action cancellation, late acknowledgement rejection, filtering after
reset and quiet restoration. Run these checks with:

```sh
./scripts/test-phone-reconstruction.sh
python3 scripts/test-phone-notification-bridge.py
```

The bridge harness uses synthetic local notifications and does not send phone
commands. On the connected Galaxy S24 Ultra, the encrypted link passed initial arrival,
immediate Mac-only muting, independent phone-notification retention, suppressed
updates, muted reconnect snapshots and quiet restoration after allowing the app.
The test restored its original preferences and removed its fixture.


### Phone media and web-link handoff (2026-10-24)

The independent companion now supports opt-in active media sharing separately
from notification mirroring. Enable **Share now playing and allow Mac playback
controls** on Android and grant notification access. The Mac receives the current
player's title, artist, album, playback state, duration and position. Its existing
music-source integration and Phone / Android controls can play, pause, toggle,
skip, stop and seek using the actions the phone player supports. Playing sessions
take priority; every command identifies the selected session so an outdated
command cannot control a newly selected player. Turning sharing off clears Mac
media and rejects controls. No audio capture, streaming or artwork is included.

Link handoff supports both directions. On Android, enable **Receive web links
from paired Mac** and allow Sapphire notifications. The Mac's new **Link handoff**
section sends a URL to a silent phone notification. Tap that notification to review
the complete URL, then choose **Open in browser**. To send the other direction, use
Android **Share → Send link to Mac** and confirm. Mac settings show the URL and
an explicit **Open received link on Mac** action. No browser opens automatically.
Only HTTP/HTTPS links up to 4,096 ASCII bytes, without embedded credentials,
spaces or backslashes, are accepted; percent-encoded paths are supported. The
latest received link is ephemeral and cleared on disconnect. Request IDs match
acknowledgements and timeouts; permission/disabled states are reported to the Mac.

Debug-only fixtures use a silent synthetic MediaSession and the fixed public
`https://example.com/sapphire-handoff-test` URL. Diagnostics expose only fixture
state, never arbitrary titles, artist names or received URLs. Device tests passed
play, pause, next, previous, exact seek, toggle, stop, sharing off/on, session
release, disabled handoff rejection, phone notification creation, opening its
review screen, and phone-to-Mac link delivery. The actual Android ACTION_SEND review screen was also exercised: confirming
**Send to paired Mac** delivered the exact public test URL. No audio played and
no browser or real messaging app was opened. The tests restore original sharing preferences.

```sh
python3 scripts/test-phone-media.py MAC_DIAGNOSTIC_PID
python3 scripts/test-phone-handoff.py MAC_DIAGNOSTIC_PID
python3 scripts/test-phone-muting.py MAC_DIAGNOSTIC_PID
```

All 126 Mac protocol checks and 17 Android JVM tests pass. macOS build/signature
verification and Android companion/helper debug and release builds pass. Release
manifest inspection confirms all three debug fixture Activities are absent.
The hotspot helper's intentional legacy target and Shizuku-mediated hidden Binder
call now have narrow, documented lint exceptions; other release checks stay on.
Third-party media-player compatibility and acoustic playback remain separate from
the silent synthetic test. Native Mac UI automation was unavailable during this
run, so transport/bridge state and the Android review Activity were checked.

### Android Bluetooth recovery and stable local signing (2026-10-24)

The Android service observes the protected Bluetooth adapter-state broadcast.
Radio-off retires the GATT server, queued writes, session keys and pending link
notification. Radio-on opens a fresh server after a short delay. Every server's
callbacks carry a generation; callbacks from a retired server cannot modify a
replacement server. Pairing records survive, and an explicitly stopped service
does not register for future radio events. The real Galaxy phone passed two
complete Bluetooth off/on cycles, regaining an authenticated connection each time
without restarting Sapphire or re-pairing:

```sh
python3 scripts/test-phone-radio.py MAC_DIAGNOSTIC_PID
```

The local build helper now reuses this Mac's existing Apple Development signing
identity instead of changing the ad-hoc identity on every rebuild. Two distinct
app builds had identical designated requirements; the updated build reopened and
read its saved pairing successfully. A first transition may require **Always
Allow** once for existing Keychain items. This does not change the login Keychain's
lock policy. See [BUILDING.md](BUILDING.md#avoiding-repeated-keychain-prompts).
