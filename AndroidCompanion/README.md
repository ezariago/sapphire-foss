# Sapphire Companion

An independent, editable Android companion for this checkout's reconstructed
Sapphire Mac integration. The Play Store APK is not modified, decompiled code is
not bundled, and its package/data/signature are not reused.

This first version provides authenticated Bluetooth pairing/reconnection, phone
battery status, automatic Mac → phone text clipboard delivery, explicit phone →
Mac text clipboard delivery and **real Android internet hotspot start/stop**.
Media controls, notification mirroring, files, calls, camera streaming and screen
sharing are not implemented.

## Build

Install JDK 17 and Android SDK platform 36/build tools, then from the Sapphire
repository root run:

```sh
./scripts/build-android-companion.sh
```

On macOS the script finds JDK 17 using `java_home` and defaults `ANDROID_HOME` to
`~/Library/Android/sdk`. Set `JAVA_HOME`/`ANDROID_HOME` for other installations.
You can also open this `AndroidCompanion` folder in Android Studio. The source ZIP
is self-contained: inside its `AndroidCompanion` folder run `./build.sh`; the two
APKs are written to `build/apks/`. Its test vectors are included, so the Mac
repository is not required to build the standalone Android project.

The script uses the pinned Gradle wrapper, runs JVM protocol tests against the
same independent crypto fixture as the Mac, and produces:

- `build/android/SapphireCompanion.apk` — `dev.sapphire.companion`, target SDK 36.
- `build/android/SapphireHotspotHelper.apk` —
  `dev.sapphire.companion.hotspothelper`, target SDK 28.

Both debug APKs use the same local Android debug signing key. Preserve that key
for updates. For distribution, configure a private release signing key and use it
for both apps; do not publish a private signing key or build secrets.

## Install and connect

```sh
adb install --user 0 -r build/android/SapphireHotspotHelper.apk
adb install --user 0 -r build/android/SapphireCompanion.apk
```

These packages coexist with `com.shariq.sapphire`. The new companion uses its own
Bluetooth service UUID (`DAB10001-5A50-434F-4D50-414E494F4E31`), avoiding collisions
with the original app's GATT service. Use the updated Mac build supplied alongside
these APKs; older Mac builds scan only for the original service. The Mac currently remembers one
companion identity at a time, so pairing the replacement switches its saved
connection to this app. The original Android app and its data remain installed.

1. Open **Sapphire Hotspot Helper**. Install/start [Shizuku](https://shizuku.rikka.app/)
   if needed, then tap **Authorize hotspot control** and approve its Shizuku
   permission request yourself. Shizuku may need restarting after a phone reboot.
2. Open **Sapphire Companion**. Allow Nearby devices and optionally its persistent
   connection notification. Tap **Pair a Mac**.
3. In the rebuilt Mac app, open Settings → Continuity → **Pair a phone**. Let it
   connect to the phone marked ready to pair.
4. Scan the Mac QR using the companion's **Scan Mac QR code** button, or paste its
   public pairing text and tap **Use pairing text**. Camera permission is only
   requested when using the scanner. The scanner works offline.
5. Compare the six digits on both devices. Confirm on the phone and Mac only if
   they match. Neither ADB nor the developer diagnostics approve pairing.
6. Wait for **Connected securely**. New Mac text copies arrive automatically;
   use **Send phone clipboard to Mac** for the reverse direction. Android's
   background clipboard restrictions still apply. Private/sensitive clips and
   received-from-Mac clips are not sent back to the Mac. Text is limited to less
   than 12,000 UTF-8 bytes.
7. In Mac Continuity settings, click **Connect to phone hotspot** and allow macOS
   Location access to scan Wi-Fi networks. This switches the Mac's Wi-Fi. The Mac
   recognizes this companion's encrypted internet-hotspot capability, and
   **Disconnect hotspot** also asks the helper to stop tethering.

The helper reads the existing Android hotspot configuration; it does not change
its name or password. For this initial implementation, select **WPA2** security in
Android hotspot settings so automatic Mac joining is supported. Mobile data,
carrier tethering entitlement and coverage still determine internet availability.

## Why two apps, and why Shizuku?

The helper is separate and targets SDK 28, but **an old target alone is not enough
on Android 16**. Current SimpleWear's helper also uses Shizuku for hotspot control;
its main app routes modern Android hotspot requests through that helper. See
[SimpleWear hotspot action](https://github.com/SimpleAppProjects/SimpleWear/blob/1b7b3a5bfe6794bbe9a73f836a21a33b46d71dc0/wearsettings/src/main/java/com/thewizrd/wearsettings/actions/WifiHotspotAction.kt).

Our helper uses user-authorized Shizuku Binder access to Android's tethering
service. It requests internet tethering, keeps carrier entitlement checks enabled
and uses the configured mobile hotspot. It never calls `startLocalOnlyHotspot`
and never substitutes Wi-Fi Direct/local-only networking when tethering fails.
If Shizuku is unavailable or access is denied, the app explains the setup needed
and provides an Android hotspot-settings button. No root installation is required
for the tested Shizuku setup; OEM/OS updates may change hidden API compatibility.

## Source map

| File | Purpose |
| --- | --- |
| `app/.../MainActivity.java` | Phone UI, permission requests, pairing confirmation, clipboard controls |
| `app/.../ScannerActivity.java` | Offline QR scanning using ZXing |
| `app/.../LinkService.java` | BLE peripheral/GATT, pairing state, protocol dispatch, foreground notification |
| `app/.../LinkEnvelope.java` | Mac-compatible JSON envelope fields and timestamps |
| `app/.../LinkCrypto.java` | P-256 ECDH, HKDF/SAS, directional ChaCha20-Poly1305 and replay window |
| `app/.../GattFrames.java` | Bounded BLE fragmentation/reassembly |
| `app/.../PairingStore.java` | Android Keystore AES-GCM wrapping of saved pairing data |
| `helper/.../HelperActivity.java` | Shizuku authorization/setup |
| `helper/.../HotspotService.java` | Narrow start/stop tethering broker and credential retrieval |
| `ipc/src/main/aidl/` | Signature-protected app/helper interface |

Each `...` above expands to `src/main/java/dev/sapphire/companion` for the main app
and `src/main/java/dev/sapphire/helper` for the helper.

The exported helper service requires a signature permission. The two APKs must
be signed with the same certificate. Other apps, including the ADB shell, cannot
call it. There is no arbitrary-command executor or unauthenticated network
listener. Pairing keys are encrypted using Android Keystore, backups are disabled,
passwords/clipboard contents are never logged, and phone commands require an
authenticated encrypted BLE session. Public QR text can be supplied to the
launcher for developer testing, but matching-code approval always stays in the UI.

## Tests

```sh
./scripts/build-android-companion.sh
./scripts/test-phone-reconstruction.sh
./scripts/test-android-companion-device.sh
# Explicitly turns the real phone hotspot on for ten seconds, then stops it:
./scripts/test-android-companion-device.sh --hotspot
```

The device test requires the test APK, a USB-debugging-authorized phone and, for
the optional hotspot check, an installed/authorized helper. It reports only
readiness/status booleans, never SSIDs, Wi-Fi passwords or pairing keys. It does
not pair the Mac or change its Wi-Fi network. `--hotspot` should be used when the
phone's hotspot is initially off, since cleanup stops tethering.

Device-tested findings are recorded in `VERIFICATION.md`.


Debug builds also write `cache/link-diagnostics.json` in the main app's private
storage. It contains only process/transport readiness, message type/byte count,
queue size and booleans indicating whether a session/code exists. It contains no
actual code, QR, peer identifier, keys, network credentials or clipboard data.
The file is unavailable to other apps; an authorized ADB developer can inspect it
with `adb shell run-as dev.sapphire.companion cat cache/link-diagnostics.json`.
Release builds do not write it.


After a phone reboot, force stop or APK update, open the companion and tap
**Start connection** if it is stopped; the saved pairing is reused. Shizuku may
also need restarting after reboot. This first version does not auto-start at boot.


### Live phone status in the notch

The companion sends battery percentage, charging state, the default mobile-data SIM’s registered network provider, Android’s cached modem signal level (0–4), and the phone’s active network kind. While connected, it checks for changes every two seconds and sends changed summaries over the authenticated Bluetooth session; the Mac also requests a refresh every 20 seconds. Android may update its cached modem readings less frequently in power-saving mode.

No phone number, SIM identifier, call history, or location is collected for this feature. `ACCESS_NETWORK_STATE` is a normal permission used only to distinguish Wi-Fi/mobile data/no active network. Missing radio data appears as unavailable. On a dual-SIM phone this summarizes the default data SIM, rather than both SIMs.

Click the phone status strip in the Mac notch to see device name, encrypted connection status, battery/charging, carrier, signal, network kind, and **Instant hotspot → Connect / Disconnect**. The hotspot button uses the same helper-backed connection flow as Settings and requires Mac Location access for Wi-Fi discovery.
