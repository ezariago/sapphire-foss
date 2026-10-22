# Device verification — 2026-10-22

Test device: Samsung Galaxy S24 Ultra (SM-S928B), Android 16. The user authorized
Shizuku for the new helper and personally approved matching pairing codes on both
devices. The original Play Store app remained installed with its data intact.

## Passed

- Both APKs compile. Five Android JVM tests cover independent Mac/Java crypto
  vectors, P-256/HKDF/SAS, directional ChaCha20-Poly1305, authentication failures,
  replay/reordering, bounded/expired GATT fragments and Mac-compatible envelope
  field types. The Mac's independent 67-check protocol suite also passes.
- Native Android device checks verify its actual ECDH/ChaCha providers, replay
  rejection and GATT reassembly.
- The exported helper rejects ADB-shell access because the caller lacks its
  signature permission. Main app and helper use matching signing certificates.
- With the user's Shizuku grant, the helper starts the **real** Android hotspot,
  returns WPA2 credentials and successfully stops it. No local-only hotspot or
  Wi-Fi Direct API is used.
- The new Bluetooth service namespace avoids collisions with the original app.
  Both apps can run together. The Mac targets the service advertised by the
  selected companion, then requires saved-key proof to authenticate it.
- The replacement pairs with the Mac using the scanned/pasted public challenge,
  matching-code approval and authenticated encrypted replies.
- A new Mac text copy arrives automatically in Android's system clipboard;
  pasting into Android Settings search reproduced the exact nonsensitive sample.
- The phone's explicit clipboard-send button delivers an authenticated
  `clipboard.update` to the Mac.
- The full Mac → encrypted BLE → companion → signature-protected helper → Shizuku
  → Android tethering flow returns valid credentials. The reverse stop command
  shuts down tethering.
- While that hotspot was active, Android's current tethering state reported
  `Upstream wanted: true`, an interface in `TetheredState`, and a mobile-data
  upstream interface. After cleanup, `Upstream wanted` returned to false. The
  Mac's existing Wi-Fi connection was not switched by this probe.
- An Android process restart and APK update preserve the Keystore-wrapped pairing.
  After starting the phone connection again, the Mac handles GATT service
  invalidation and stale transports automatically. In the device test, a fresh
  phone process regained an authenticated session in approximately five seconds,
  without another QR or approval, while the original app was also running.

## Remaining verification and scope

Actual Mac Wi-Fi association and an internet request through that Wi-Fi connection
still require macOS Location approval. The tested probe validates tethering,
cellular upstream and credential exchange while leaving Mac Wi-Fi unchanged.

The offline camera scanner compiles; pairing was device-tested through public QR
text entry rather than physically scanning with the camera.

This is an independent first version, not recovered original private source.
Media controls, notification mirroring, files, calls, camera streaming and screen
sharing remain unimplemented. Android background clipboard rules still limit
phone → Mac automation, so that direction uses an explicit send action.


## Artifact checks

The standalone Android source ZIP was extracted into a separate folder and its
own `./build.sh` successfully built both APKs and passed all five JVM tests without
accessing the Mac repository's source or fixture files. Both installed Android
APKs match their delivered files byte for byte, and both signatures verify with
the same certificate. The final Mac ZIP was extracted, passed strict nested
signature verification and matched the tested executable.


## Live device status and notch panel

- On the Galaxy S24 Ultra, native device checks read the registered carrier
  `INDOSATOOREDOO` and a valid 4/4 modem level, plus battery status, without any
  runtime phone/location permission. The companion now publishes changed status
  summaries every two seconds over its authenticated link.
- The Mac protocol suite includes missing/legacy telemetry, zero vs. unknown
  signal, out-of-range/fractional signal values, carrier control characters and
  unknown network kinds.
- The formerly empty notch detail route now displays device status and hotspot
  Connect/Disconnect controls. Native SwiftUI previews of the actual panel source
  were rendered in connected, connecting, hotspot-connected and offline states.
