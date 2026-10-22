# Building Sapphire FOSS locally

## Current status

The repository is cloned at upstream commit
`792f9b4ea3d556d7566fbc38592fe54e88d89dc0`.
Sapphire 3.5 built successfully in Release configuration for Apple silicon using
Xcode 27.1 on macOS 27.0.1. Its code signature passed verification, the Settings
window rendered and responded, and a clean quit and normal relaunch succeeded.
The archive is `build/Sapphire-local.zip`. Full Xcode is required to rebuild;
Apple Command Line Tools alone are insufficient.

## Requirements

- A Mac running macOS 14 or newer (the application's deployment target).
- Full Xcode. Use a current version; this project was last upgraded with Xcode 26.5.
- Open Xcode once, accept its license, and complete its component installation.
- Internet access for Swift Package Manager dependencies.
- Python 3, available with the Apple developer tools on this Mac.

## Build this prepared checkout

In Terminal:

```bash
cd sapphire-foss
./scripts/build-local.sh
```

On this Mac, GitHub HTTPS transfers repeatedly stalled. The verified workaround
uses this Mac's existing GitHub SSH login over port 443:

```bash
SAPPHIRE_GITHUB_SSH=1 ./scripts/build-local.sh
```

That option requires an SSH key already authorized with GitHub. It scopes the
transport change to the build and stores GitHub's public host key under `build/`;
it does not edit your SSH configuration or global Git settings. The host key is
checked against [GitHub's published fingerprints](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints).

The script automatically uses `/Applications/Xcode.app` when it exists. If you
installed Xcode elsewhere, specify its developer directory:

```bash
DEVELOPER_DIR="/path/to/Xcode.app/Contents/Developer" ./scripts/build-local.sh
```

The first build downloads the dependencies pinned in `Package.resolved` and can
take some time. A successful run verifies the application's code signature and
produces:

- App: `build/DerivedData/Build/Products/Release/Sapphire.app`
- Zip: `build/Sapphire-local.zip`
- Logs: `build/logs/resolve.log` and `build/logs/build.log`

The script exits on a failed dependency resolution, compilation, or signature
check. The existence of a generated project alone does not indicate a successful
build.

## Run

Quit the installed Sapphire from its menu before starting the local copy. Then:

```bash
open build/DerivedData/Build/Products/Release/Sapphire.app
```

Sapphire runs around the notch without a normal Dock window. Open the same app
again (or double-click it in Finder) to display Settings.

On first launch, follow the app's onboarding. Grant Accessibility and any other
permissions required by the features you choose in System Settings → Privacy &
Security. The local build uses the upstream app identifier, so it may share
preferences with the installed copy. Do not run both copies at once.

## What the helper changes

`scripts/prepare-local-build.py` generates a separate Xcode project under
`build/Local/`; it leaves the original `Sapphire.xcodeproj` untouched. It:

- Includes the public stubs that the upstream app target currently excludes.
- Excludes the older Gemini placeholder because the checkout now includes its
  implementation, and includes `Sapphire/Stubs/PublicBuildCompatibility.swift`
  for missing public interfaces. Unavailable private features remain inert.
- Points the File Provider target at its supplied public placeholder.
- Converts build-script arrays into executable script text.
- Removes the author's Crashlytics symbol-upload build step.
- Resolves system frameworks through the selected macOS SDK.
- Uses ad-hoc local signing instead of the author's development team and
  provisioning entitlements.
- Copies and signs the media playback frameworks and scripts in the Resources
  directory where the app loads them at runtime.
- Uses HTTP/1.1 for Git downloads within the build process to avoid stalled
  GitHub transfers on this connection; it does not change global Git settings.
- Limits package download concurrency and retries failed dependency resolution
  up to three times while reusing completed downloads.

The source also includes a startup fix in
`Sapphire/Services/Gemini/GeminiLiveManager.swift`: its audio engine and player
are initialized lazily, so opening Sapphire does not wait for macOS audio
component discovery before displaying the interface.

This is a local development build. It is not notarized for distribution.
Features requiring private implementations, developer-service credentials, app
groups, or provisioned system extensions may be unavailable. In particular, the
public camera and audio-driver targets are placeholders. This helper does not
install privileged helpers or system drivers.

This checkout also includes an independent, partial reconstruction of Phone /
Android integration. See [PHONE-RECONSTRUCTION.md](PHONE-RECONSTRUCTION.md) for
its scope, pairing steps, evidence, tests and remaining limitations. It does not
recover all original private source. `SAPPHIRE_FAST_BUILD=1` disables app
optimization for faster device-test iterations; omit it for optimized builds.

## Clone on another Mac

The Mac repository includes the build helpers, compatibility code and phone
integration. The Android companion and helper share a separate
[sapphire-android-companion](https://github.com/ezariago/sapphire-android-companion) repository. No separate local patch is needed:

```bash
git clone https://github.com/ezariago/sapphire-foss.git
cd sapphire-foss
./scripts/build-local.sh
```

To inspect the generated project in Xcode after preparation:

```bash
python3 scripts/prepare-local-build.py
open build/Local/Sapphire.xcodeproj
```

Select the Sapphire scheme and My Mac as the destination.

## Troubleshooting

- **“Full Xcode is required”**: finish installing and opening Xcode. Installing
  only `xcode-select --install` is insufficient.
- **License or first-launch component error**: open Xcode and complete its setup,
  then rerun the build helper.
- **Package download failure**: check the network and `build/logs/resolve.log`,
  then rerun the helper. Keep the pinned dependency versions.
- **Compiler error**: inspect `build/logs/build.log`. These local fixes target
  the recorded source commit and may need updating for future upstream changes.
- **The app appears to do nothing**: Sapphire is a menu-bar/notch app. Check the
  menu bar, onboarding, and Accessibility permissions.

The upstream `Sapphire.pkg` at the recorded commit is empty; it is not a usable
installer. The upstream README points users to its GitHub releases for official
prebuilt installers.

## Android companion and helper

Clone the Android repository beside this Mac checkout, then build both APKs:

```sh
git clone https://github.com/ezariago/sapphire-android-companion.git ../sapphire-android-companion
./scripts/build-android-companion.sh
```

The wrapper uses `../sapphire-android-companion` by default. Set
`SAPPHIRE_ANDROID_SOURCE` to use another checkout. APKs are copied to
`build/android/`. Android Studio can open the Android repository independently.
Both Android apps must use the same signing certificate for their Binder service.
