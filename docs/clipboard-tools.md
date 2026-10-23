# Clipboard enhancements

Added 2026-10-24; opt-in through the existing Clipboard settings.

- Searchable history picker uses the existing encrypted history, supports text,
  files and images, previews, Copy and Paste, and a configurable global shortcut.
  Pasting returns to the original app and verifies it is still frontmost before
  issuing the synthetic paste shortcut. Accessibility is required for that step;
  Copy remains available without it.
- Auto-clear observes clipboard revisions and uses monotonic time. A new copy
  resets the deadline. Clearing on delay, sleep and screen lock empties only the
  system clipboard, not saved history. The clipboard revision is rechecked on the
  serialized write lane to avoid clearing a newer copy.
- URL cleaning rewrites only one plain-text HTTP(S) URL. Rich text, images,
  multiple items and unknown/concealed clipboard types are left intact. Tracking
  parameters and configured custom keys are removed without rebuilding retained
  query values. Known signed URLs are preserved unchanged. Other automatic
  clipboard consumers may observe the original before the asynchronous rewrite.
- Finder cut/paste uses native Copy and Move Item Here. Move is issued only when
  both clipboard revision and file paths still match the captured cut operation.
  Editing a Finder text field retains normal text cut/paste behavior. The optional
  F2 rename maps to Finder's native Return action. PNG image pasting writes a new
  UUID-named file without overwriting, using Finder's insertion location; this
  may require Automation permission. It never deletes source files itself.

`./scripts/test-clipboard-tools.sh` verifies URL encoding/signature preservation,
tracking removal/idempotence and revision-based expiry. Full app builds verify
integration. Native shortcut conflicts, actual paste into third-party apps, fast
Finder cut/paste timing, Automation approval, image/file clipboard cases and
physical sleep/lock remain manual smoke tests. These are recorded as remaining
verification, not claimed complete merely because the code compiles.
