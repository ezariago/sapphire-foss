# Public window and Dock implementations

Added 2026-10-24. All controls remain opt-in.

| Path | Implementation | Evidence and remaining work |
| --- | --- | --- |
| Dock presets | Capture pinned applications and Dock position/size/autohide/magnification; validated, versioned import/export; atomic preference backup before application; restart Dock | Isolated preference-domain tests pass. Actual Dock appearance and restoration need a manual smoke test. Legacy name-only presets cannot be applied until recaptured. |
| Window switcher | AX window enumeration, Command/Option-Tab cycling, reverse cycling, modifier-release activation, Escape cancellation | Full app compiles. Accessibility permission and real input/Spaces behavior remain manual checks. |
| Dock previews | AX Dock item hit testing and delayed window picker; ScreenCaptureKit window thumbnails when Screen Recording is allowed; icon/title fallback otherwise | Full app compiles. Alternate trigger/layout variants and live thumbnail refresh remain open. |
| Dock clicks | Minimize or hide a frontmost app after its Dock icon is clicked; basic window activation for cycle | Full app compiles. Real Dock timing, complete cycling and alternate-display behavior need device checks. |
| Auto-quit | Track apps that had windows; request normal termination after their last window remains closed; excluded apps and AX-query failures are respected | No force termination. Save dialogs remain under the target app's control. Manual app compatibility checks remain open. |
| Quit/close protection | Shared event hook with hold, double-press and extra-modifier policies, app exclusions and per-close configuration | Isolated state-machine tests pass for timing, repeat suppression and app isolation. Hold uses keyboard repeat events; actual keyboard/input-method verification remains open. Menu/app-initiated exits are outside this hook. |
| Green maximize | Cached AX green-button hit; maximize to the display's usable frame and restore previous geometry; Option-click/full-screen exit keep native behavior | Full app compiles. Real button roles, app size constraints and multi-monitor hot-plug need manual verification. |

`./scripts/test-dock-layouts.sh` and `./scripts/test-quit-protection.sh` are included
in macOS CI. The former uses a fresh UUID-named CFPreferences domain and does not
change the real Dock. Context-menu services, hinge animations, Dock locking and
preset shortcut configuration remain on the README roadmap. A successful compile
is not recorded as end-to-end feature parity.
