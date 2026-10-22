<div align="center">
<img width="220" height="220" alt="Sapphire" src="https://github.com/user-attachments/assets/1e3ef88f-9849-4896-88d2-5294841a0062" />

  <h1>Sapphire FOSS</h1>
  <p><b>Working toward a fully free and open-source Sapphire.</b></p>
  <p>
    <a href="BUILDING.md">Build for macOS</a> ·
    <a href="AndroidCompanion/README.md">Android companion</a> ·
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
- Live phone battery/charging, carrier and signal strength in the notch, with a
  device-status panel and instant hotspot controls.
- Real Android mobile hotspot start/stop through a user-authorized Shizuku helper.
  Automatic Mac Wi-Fi joining requires Location permission; full internet-through-
  Mac verification is still pending.

See [Phone / Android implementation notes](PHONE-RECONSTRUCTION.md) and
[device verification](AndroidCompanion/VERIFICATION.md) for tested behavior and
remaining limitations. Calls, notification mirroring, media control, file browsing,
camera streaming and screen sharing are not implemented in the replacement companion.

## Build and install

```sh
git clone https://github.com/ezariago/sapphire-foss.git
cd sapphire-foss
./scripts/build-local.sh
open build/DerivedData/Build/Products/Release/Sapphire.app
```

Full Xcode and its initial setup are required. Read [BUILDING.md](BUILDING.md) for
requirements, signing, permissions and troubleshooting. Android companion/helper
build and installation steps are in [AndroidCompanion/README.md](AndroidCompanion/README.md).

Builds use local signing and are not notarized. No fork-specific prebuilt release
is published yet; upstream downloads do not include this fork's changes.

## License and attribution

The upstream [GNU Affero General Public License v3](LICENSE) is retained. Fork
additions are provided under the same license; third-party components retain their
respective notices (see also [Android third-party notices](AndroidCompanion/THIRD-PARTY.md)).
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
