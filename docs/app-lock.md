# App Lock and Focus shields

Implemented 2026-10-24 in the public build, opt-in and disabled by default.

- Protected application activation creates opaque privacy panels on all displays.
  No screenshot of the protected content is retained. Switching to an unrelated
  app removes the panels; returning to the protected app restores them.
- Touch ID/system authentication uses LocalAuthentication. The optional password
  field checks the current Mac user's login password through OpenDirectory in
  process. No password is persisted or sent to a subprocess.
- Authenticated apps remain unlocked until the configured leave/idle/sleep policy
  relocks them, the Mac screen locks, or the user chooses Lock Now. An auth result
  arriving after a relock or authentication-setting change cannot unlock the app,
  including a rapid disable/re-enable before the UI refreshes. Switching to
  Sapphire deliberately also relocks, including the first departure after startup;
  accessory authentication agents do not.
- Three failed password attempts impose a 30-second retry cooldown measured
  with monotonic uptime, so a wall-clock change cannot bypass it. The bounded
  failure log is in-memory and contains app/time/method, never passwords.
- Changing an enabled configuration requires system authentication. Authorization
  is discarded when Settings disappears, the app deactivates, or the Mac sleeps.
- Focus shares the shield layer, with allow/snooze controls at minimal intensity
  and cooldown-based access at strict intensity. Standard/strict Focus retains
  its explicit terminate/force-terminate behavior; use those modes with care.

This is a session privacy and productivity feature, not an OS security boundary.
It cannot prevent quitting Sapphire, inspecting another process, notification
previews, or a brief pre-shield frame during app activation. Lock macOS when
leaving a machine unattended. App Lock does not terminate protected applications
or automatically reopen them. Inherited camera, prevent-process-launch,
auto-close and panic-key settings are not exposed as supported behavior here.

## Verification

- `./scripts/test-app-lock.sh`: injected authentication fixtures test denial while
  disabled, empty-password rejection, failed/successful password paths, successful
  system auth, relock, cooldown expiry, accessory/regular app transitions,
  unsupported Face ID and stale-auth/configuration-race rejection.
  No real login password or biometric approval is used by these tests.
- `./scripts/test-app-protection.sh`: launches a temporary signed GUI fixture and
  verifies real workspace activation, visible shield creation, unblock/reblock
  and complete teardown. It does not enable App Lock on the user's own apps.
  `--panel-only` skips activation and directly shields the temporary fixture,
  testing panel creation, simulated display geometry changes and teardown behind
  a locked Mac session. This mode does not prove workspace activation or monitor
  hot-plug. The overnight session became locked: the activation test could not
  acquire focus (`com.apple.loginwindow` remained frontmost); no unlock was tried.
- Full local app build/signature verification is recorded in `build/logs/`.

Remaining manual checks: real Touch ID/password success/cancel, fast-user-switch,
Mission Control and multiple Spaces/full-screen transitions, monitor hot-plug
(panel geometry refresh has isolated fixture coverage), physical sleep/wake and screen-lock recovery. These remain on the README roadmap.
