# Inline emoji suggestions

Emoji settings now have a separate **Suggest emoji while typing colon aliases**
opt-in, off by default. It is independent of the system picker shortcut and does
not inherit the older placeholder colon preference. Type `:smi` or `:smile:` in
a compatible external text editor, then click a choice beside the caret. The
curated local catalog contains 24 aliases; it is not a full emoji database.
Suggestions use base emoji. The macOS Emoji & Symbols picker remains available
for its full library, search and skin-tone controls.

The popup is nonactivating and never consumes keyboard input. There is no Tab/
arrow selection or automatic closing-colon expansion. Offers expire after five
seconds; continued typing, navigation, scrolling, outside clicks, app changes,
settings changes, lock/sleep or event-tap resets discard old offers. A shared
excluded-app list applies to both picker and inline suggestions. Sapphire's own
text fields, secure/protected controls and input-method composition are skipped.

The adapter uses Accessibility parameterized text ranges: up to 64 UTF-16 units
before the caret and one after, with character-count metadata. It does not fetch
the full field, read the clipboard, post keys, capture the screen or write editor
text to disk. Fields over one million UTF-16 units, unknown ranges or unsupported
range/bounds/edit APIs decline. Only a matched colon prefix is selected/replaced
after explicit choice. Exact text/selection, app/PID/launch identity, configuration,
secure-input/console/shield status and offer age are rechecked. Failed writes
restore selection only when the original state still matches. As with other AX
edits, external app changes cannot be made atomic with the final native call.

`./scripts/test-emoji-inline.sh` passes prefix/boundary/caret/UTF-16/catalog and
geometry checks, stale transaction refusal, production manager/panel/AX adapter
compilation and opt-in/disable lifecycle with inert hooks. It renders the real
choice view offscreen (`build/emoji-inline-tests/panel.png`); the render was
visually reviewed. The full local Mac app build passed.

`./scripts/test-emoji-inline-native.sh` also passed on this Mac, using only its
own background native editor and secure-field fixtures. It verifies bounded
parameterized reads, selected-text replacement, emoji/caret result and refusal
of the synthetic secure field. Both a short prefix and a long emoji prefix whose
window begins inside a UTF-16 surrogate pair pass, with preceding content intact.
It requests no permission and returns 77 if AX trust is unavailable; it is not a
headless CI check. No user document, clipboard, key posting or foreground routing
was involved. Real global typing, popup click/focus behaviour, permission changes
and third-party editor/IME compatibility remain attended checks. This is a
click-to-insert public subset, not full Slack-style keyboard/picker parity.

## Checkpoint limits

The input gate now tracks up to 16 observed keys and inspects only after all
are released, including out-of-order releases. Repeated/unknown keys, overflow,
context changes and stale offers invalidate the pending inspection. Dedicated
rollover fixtures and the full local app build pass. Real popup click/focus
routing remains unverified; text-range insertion itself passes native tests.

At the final checkpoint the consolidated configured-script run stopped at
`test-media-tools.sh`: Apple's media runtime returned
`e5rt_execution_stream_operation_create_precompiled_compute_operation_with_options`
error 13. The full 31-script regression is not a pass. Feature-specific emoji,
profile and mouse checks and their full local app builds passed; the media
runtime failure needs investigation after usage is available again.

The later 25 October OCR compatibility checkpoint reran all 31 configured shell
checks and the isolated file-transfer harness successfully (32 checks). This
supersedes the media-blocked consolidated run above; it does not establish real
global typing/popup or third-party editor compatibility.
