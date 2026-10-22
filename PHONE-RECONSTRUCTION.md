> Update: an independent editable Android companion and real hotspot helper now
> live in [AndroidCompanion](AndroidCompanion/README.md). The local-only hotspot
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
- Display notification previews received from the phone.

Not implemented: Wi-Fi/bulk transfer, file/storage browsing, screen mirroring, extended display, virtual camera/microphone, SMS/calls, Android widgets, image/file clipboard, hotspot, handoff and universal keyboard/mouse. Their protocol identifiers may be visible in a binary, but each still requires substantial implementation and verification. No account/subscription backend is reconstructed or changed.

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

`AndroidCompanion/` is a standalone Android Studio/Gradle project. Its main app
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

See `AndroidCompanion/README.md` for build/setup/modification instructions and
`AndroidCompanion/VERIFICATION.md` for the precise tested scope. Actual Mac Wi-Fi
association still requires Location approval; no network switch was performed by
the diagnostic hotspot probe.


### Notch device status (2026-10-22)

The replacement companion broadcasts changed battery/charging, mobile provider, 0–4 modem signal level and active network summaries over the encrypted Bluetooth connection. It checks every two seconds; periodic refresh requests remain supported. Carrier/signal use the public Android telephony summary APIs without runtime phone or location permission. Unknown telemetry stays unavailable rather than appearing as a fabricated signal strength.

The former empty `ContinuityNotchDetailView` now opens a live device panel with status and Instant Hotspot controls. The compact notch status shows carrier and four independently filled signal bars. Hotspot actions reuse the existing authenticated helper/CoreWLAN flow, including permission handling, busy states and disconnect.
