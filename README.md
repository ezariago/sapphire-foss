<div align="center">
<img width="220" height="220" alt="Sapphire" src="https://github.com/user-attachments/assets/1e3ef88f-9849-4896-88d2-5294841a0062" />

  <h1>Sapphire FOSS</h1>
  <p><b>Working toward a fully free and open-source Sapphire.</b></p>
  <p>
    <a href="BUILDING.md">Build for macOS</a> ·
    <a href="https://github.com/ezariago/sapphire-android-companion/blob/main/README.md">Android companion</a> ·
    <a href="https://github.com/cshariq/Sapphire">Original project</a>
  </p>
</div>

<br>

Sapphire FOSS is an independent fork of [Sapphire](https://github.com/cshariq/Sapphire),
the macOS notch app created by Shariq Charolia and its contributors. Our goal is
to make Sapphire fully FOSS: publish the code needed to build it, replace missing
private implementations with open-source alternatives, and let anyone inspect,
modify and share the Mac app and its Android companion.

This is a work in progress. Several upstream features still have compatibility
placeholders, and a complete source/dependency audit and replacement of bundled
binary-only components remain to be done. The project is not yet a complete
replacement for every feature of the original app. Thanks to the upstream authors
for the foundation this work builds on.

## What this fork adds

- A documented macOS build workflow with local signing and compatibility code for
  unavailable upstream modules.
- An editable Android companion and hotspot helper, with encrypted Bluetooth
  pairing and reconnection.
- Automatic Mac → Android text clipboard delivery and manual Android → Mac delivery.
- Opt-in Android notification mirroring with a Mac list, notch alerts, dismissal,
  supported actions/replies and optional macOS banners. Android notification access
  and explicit sharing must be enabled on the phone.
- Live phone battery/charging, carrier and signal strength in the notch, with a
  device-status panel and instant hotspot controls.
- Real Android mobile hotspot start/stop through a user-authorized Shizuku helper.
  Automatic Mac Wi-Fi joining requires Location permission; full internet-through-
  Mac verification is still pending.

See [Phone / Android implementation notes](PHONE-RECONSTRUCTION.md) and
[device verification](https://github.com/ezariago/sapphire-android-companion/blob/main/VERIFICATION.md) for tested behavior and
remaining limitations. Calls, file browsing,
camera streaming and screen sharing are not implemented in the replacement companion.

## Repositories

- [sapphire-foss](https://github.com/ezariago/sapphire-foss) — macOS app.
- [sapphire-android-companion](https://github.com/ezariago/sapphire-android-companion) — Android companion and hotspot helper in one Gradle project, including their shared Binder interface.

## Build and install

```sh
git clone https://github.com/ezariago/sapphire-foss.git
cd sapphire-foss
./scripts/build-local.sh
open build/DerivedData/Build/Products/Release/Sapphire.app
```

Full Xcode and its initial setup are required. Read [BUILDING.md](BUILDING.md) for
requirements, signing, permissions and troubleshooting. Android companion/helper
build and installation steps are in [the Android README](https://github.com/ezariago/sapphire-android-companion/blob/main/README.md).

Builds use local signing and are not notarized. No fork-specific prebuilt release
is published yet; upstream downloads do not include this fork's changes.

## Roadmap / implementation checklist

Reviewed against this fork's source on **2026-10-24**. Checked items have an
implementation and recorded build/device evidence; unchecked items are remaining
work, not delivery promises. A visible setting, protocol identifier or buildable
stub does not mean the feature works. The Android items require coordinated work
in the [companion repository](https://github.com/ezariago/sapphire-android-companion).
See the [24 October overnight handoff](docs/overnight-handoff.md) for implementation
evidence, native checks and remaining blockers.

### Implemented foundation

- [x] Local macOS build/signing workflow and separate editable Android companion/helper.
- [x] Encrypted Bluetooth pairing, saved-key reconnection and transport recovery.
- [x] Automatic Mac → Android text clipboard and manual Android → Mac text clipboard.
- [x] Live phone battery, charging, carrier/signal and notch device panel; Android
  internet hotspot start/credentials/stop through the authorized Shizuku helper.

### FOSS foundation and distribution

- [x] Replace inherited subscription/account gates with a FOSS feature-access
  policy. Implemented features are available without an account or subscription;
  this does not implement the missing feature code.
- [ ] Audit bundled dependencies, licenses and source/build provenance; publish
  reproducible builds or replacements for binary-only components, including
  `MediaRemoteAdapter.framework`, `SapphireMediaQueue.framework` and compiled
  Face ID models. An initial [hashed input inventory and blocker audit](docs/audit/README.md)
  is available; source replacements and full license review remain open.
- [x] Replace the public app-update validation shim with actual code-signature
  and installed signer requirement verification, including rejection fixtures.
- [ ] Add automated macOS build/test CI and fork-specific release artifacts,
  with a documented signing/notarization and update distribution workflow.
  [Build/test CI](.github/workflows/macos.yml) and development artifacts are added;
  hosted build/test runs have passed and uploaded development artifacts. A public
  signed/notarized release and update distribution workflow remain pending.

Evidence: [subscription shim](Sapphire/Stubs/SubscriptionCore.swift),
[FOSS feature wrappers](Sapphire/Stubs/PremiumFeatureKit.swift),
[update validation shim](Sapphire/Stubs/AppSecurity.swift), [build notes](BUILDING.md).

### Missing or partial macOS features

- [ ] Implement App Lock authentication/enforcement and the shared app shields
  used by Focus app blocking. Existing Focus session and website-blocking code
  does not supply the missing app-enforcement layer. Core system/password
  authentication, session shields, sleep/idle/leave relocking and configuration UI
  are now implemented and tested with an isolated auth provider and real Mac app.
  A privacy shortcut now relocks and requests hiding protected apps. Camera
  authentication, process-launch prevention and complete
  permission/hardware verification remain open. See [App Lock evidence](docs/app-lock.md).
- [ ] Implement Dock previews, window switcher, Dock click behavior, auto-quit,
  quit protection, green-button maximize, context-menu enhancements, hinge
  animations and Dock layout import/application. Public implementations for
  presets, AX window selection/previews, click actions, auto-quit, quit protection
  and green-button maximize are added; [implementation/test status](docs/window-controls.md)
  records remaining UI variants and device verification.
- [ ] Implement mouse controls, focus-follows-mouse, extra-click filtering,
  keyboard debounce, Super Key, emoji suggestions and text snippets; complete
  their settings and shortcut configuration UI. Keyboard debounce now has a public
  event-filter implementation and per-key overrides. [Extra-click filtering](docs/mouse-click-filter.md)
  and [focus follows mouse](docs/focus-follows-mouse.md) also have public code and
  isolated tests; native [keyboard](docs/keyboard-debounce.md) and mouse verification
  remains open. [Discrete mouse-wheel direction and speed](docs/mouse-wheel.md)
  now also have public code; acceleration, button remapping and smooth/linear
  scrolling remain unimplemented. [Command-key Hyper mapping](docs/super-key.md)
  implements the supported Super Key source keys; Caps Lock and native verification
  remain open. [Text snippets](docs/text-snippets.md) now have guarded Accessibility
  replacement and date/time/clipboard placeholders; native editor verification and
  emoji suggestions remain open. The [system Emoji & Symbols shortcut](docs/emoji-picker.md)
  now has configuration and app exclusions; inline colon suggestions are unimplemented.
- [ ] Implement the clipboard picker, automatic clipboard clearing, URL cleaning
  and Finder cut/paste enhancements; retain the existing clipboard history code.
  These now have public implementations and policy tests; [native interaction
  verification remains open](docs/clipboard-tools.md).
- [ ] Implement media optimization and OCR, screenshot text monitoring and Circle
  to Search. Native image/PDF/audio/video compression, local OCR and opt-in
  screenshot text monitoring are added; [test coverage and remaining checks](docs/media-tools.md)
  distinguish fixtures from live screen/video verification. Circle to Search and
  automatic clipboard optimization remain open. File conversion is separate.
- [ ] Implement the DMG installer and its default-handler integration; complete
  the archive settings UI around the existing archive extractor. Both now have
  public code, including staged signed-app installation and a passing real-DMG
  fixture; [default-handler/permission and failure recovery checks](docs/dmg-installer.md)
  remain open.
- [ ] Complete storage workspace/detail/widget UI and monitoring settings,
  adapter-power readings and menu-bar profile automation. Storage scanning and
  system statistics already have public implementations. The [storage workspace
  and notch capacity views](docs/storage-workspace.md) now expose scans, file/category/
  duplicate inspection and reviewed per-item Trash actions; native permission,
  Trash recovery and remaining visualization/workflow checks are still open.
  [Monitoring settings and delivery guards](docs/monitoring.md) now configure the
  public readout/alert engines; native permissions, alert delivery, adapter readings
  and profile automation remain open.
  [Power display availability](docs/power-readings.md) now distinguishes missing
  adapter telemetry from zero and removes the fabricated system-load fallback;
  real charger/sensor verification remains pending.
- [ ] Implement the missing 8D/surround audio views and verify their integration
  with the existing audio engine after feature access is available. Public
  [per-app controls and bounded parameter wiring](docs/spatial-audio.md) are added;
  permission, live routing and acoustic verification remain open.
- [ ] Implement sports scores/commentary and finance quotes, including settings,
  widgets, players and live activities; the current providers return no data.
- [ ] Implement Intelligence task execution, screen perception, memory/monitoring
  and Blip UI. Gemini Live has public source and is excluded from the legacy
  Gemini stub by the local build helper.
- [ ] Implement Smart Inbox OTP/parcel monitoring and actions around the existing
  data models and verification-code detector.
- [ ] Replace the camera, virtual microphone, File Provider and Finder Sync
  extension placeholders with functional implementations and installation/setup.

Evidence: [feature manager stubs](Sapphire/Stubs/PremiumFeatureManagers.swift),
[feature model stubs](Sapphire/Stubs/PremiumFeatureModels.swift),
[view stubs](Sapphire/Stubs/PremiumFeatureViews.swift),
[remaining public stubs](Sapphire/Stubs), [extension placeholders](PublicExtensionStubs).
The [older parity gap map](docs/parity/vorssaint-gap-map.md) is historical context;
its individual findings need rechecking against the current source.

### Android / Continuity feature parity

- [x] Implement opt-in phone media state/playback commands and Mac phone-media
  presentation, verified with a silent Android MediaSession fixture. Third-party
  media-player and acoustic playback checks remain open.
- [x] Implement opt-in notification posts/updates/removals, reconnect snapshots,
  Mac list/notch alerts, optional banners and supported dismissal/actions/replies.
- [x] Verify notification arrival/update/removal, actions, replies, dismissal
  and quiet reconnect using the debug fixture on a real Android phone and Mac.
- [ ] Extend notification verification to third-party apps, permission revocation,
  locked-phone/OEM behavior and optional macOS banners.
- [ ] Implement SMS and calls, including the Mac message/call action bridges.
- [ ] Implement authenticated Wi-Fi/bulk file transfer, phone storage browsing
  and image/file clipboard delivery beyond the current text-only transport.
- [ ] Implement screen mirroring, extended display and phone camera/microphone
  streaming, including photo capture and document scanning.
- [ ] Implement Android widgets/external live activities, handoff/browser-tab
  sharing, universal keyboard/mouse, Focus synchronization and remote/relay access.
- [ ] Implement phone-mediated earbud status/control/handoff and active-peer
  selection; these compatibility methods currently do nothing.

Evidence: [Continuity bridge](Sapphire/Stubs/ContinuityCore.swift),
[compatibility methods](Sapphire/Stubs/PublicBuildCompatibility.swift),
[phone implementation notes](PHONE-RECONSTRUCTION.md).

### Implemented paths still awaiting end-to-end verification

- [ ] Verify actual Mac Wi-Fi association and internet access through the phone
  hotspot after Location permission is granted. Android cellular tethering and
  encrypted credential delivery have been tested; full Mac internet access has not.
- [ ] Verify reconnection after physical Mac sleep/lid-close and radio recovery
  on real devices. The current sleep/wake handler test exercises notifications
  without putting the Mac to sleep.
- [ ] Record a feature-by-feature macOS smoke-test matrix, including permissions,
  supported OS/hardware and failure recovery, before claiming upstream parity.

See [recorded device checks and limitations](PHONE-RECONSTRUCTION.md) for the
distinction between protocol tests, simulated lifecycle checks and hardware tests.

## License and attribution

The upstream [GNU Affero General Public License v3](LICENSE) is retained. Fork
additions are provided under the same license; third-party components retain their
respective notices (see also [Android third-party notices](https://github.com/ezariago/sapphire-android-companion/blob/main/THIRD-PARTY.md)).
Sapphire FOSS is independently maintained and is not an official upstream release.

## Sapphire features

The overview below is inherited from upstream. Availability varies in this fork;
it is not a claim that every feature has been rebuilt or tested.

<div style="display: flex; flex-wrap: wrap; gap: 16px; justify-content: center;">

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Nearby Share</h3>
    <p>Allows sharing files, pictures, videos, websites, and more from Android to your mac!</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Now Playing</h3>
    <p>Displays currently playing media of all types in the notch (works with macOS 15.5 as well), and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Advanced Audio Features (Beta)</h3>
    <p>Adjust individual app volumes, device volumes, app EQs and device EQs right from the notch</p>
  </div>
  
  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Eye Break</h3>
    <p>Health should always be your priority. With the sleek notch UI, a reminder is given every 20 minutes to look 20 feet away for 20 seconds, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Weather</h3>
    <p>Current weather is persistently shown in the notch, so you're in the know about your surroundings, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Gemini</h3>
    <p>Share your screen and discuss topics conveniently using Gemini Live, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Calendar</h3>
    <p>See upcoming events and get alerted for ongoing events, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Lock Screen</h3>
    <p>See the weather, your music, and upcoming calendar events on your Mac's lockscreen, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">File Shelf</h3>
    <p>Airdrop and store files conveniently with access to the file shelf, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Snap Zones</h3>
    <p>Snapping windows using macOS's built-in snapping tools is limited and leaves a gap between windows. Sapphire provides a versatile and customizable window snapping system, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Music</h3>
    <p>View now playing media on the notch with additional information and controls when the now playing media is expanded, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Bluetooth</h3>
    <p>Get a notice when a Bluetooth device connects to your Mac, and more.</p>
  </div>

  <div style="border: 1px solid #30363d; border-radius: 8px; padding: 16px; width: 300px; background-color: #1c1c1e;">
    <h3 style="margin-top: 0;">Caffeinate</h3>
    <p>Caffeinate your Mac with a press of a button, and more.</p>
  </div>

</div>
