# System Emoji & Symbols shortcut

Added 24 October 2026, opt-in in Emoji settings. The existing native picker
shortcut can be recorded or reset to Control–Command–Space. It uses Sapphire's
shared conflict-aware shortcut dispatcher and requires Accessibility for global
input. Bare/Shift-only shortcuts are rejected to avoid intercepting ordinary
typing. Conflicts or disabled shortcut IDs are shown in settings. A button also
requests the picker when the feature is enabled.

The manager uses AppKit's public `orderFrontCharacterPalette` action. macOS owns
search, skin-tone choices and insertion; Sapphire does not inspect or replace
the target field, post input or change the clipboard. This is a system picker
integration, not a bundled emoji/alias database. It does not implement inline
colon suggestions or use the inherited Sapphire skin-tone setting, which are
not exposed as working controls.

Current enablement, exclusions and a configuration generation are checked when
queued shortcut actions execute. Changed/deleted/disabled bindings and actions
from a stopped manager are skipped. The current regular foreground app must be
known and not excluded, and secure event input must be inactive. Exclusions and
shortcut settings persist in the existing settings model. Teardown unregisters
the provider; startup supports registering it again.

The full app build checks integration. The picker is not automatically opened
over the user's app as a test, and no emoji is inserted into user content.
Actual shortcut conflicts with the OS binding, picker presentation and insertion
into third-party apps, secure-input transitions and permission recovery remain
attended native checks. An API request has no success result; the status text
reports only that macOS was asked to present its picker. Inline colon suggestions
remain on the README roadmap.
