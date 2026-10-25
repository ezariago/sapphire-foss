# Region text search

Media Tools → Screen text search is a separate opt-in, off by default even when
the older Circle to Search placeholder setting was enabled. The configured
Control-Shift-C shortcut uses the shared dispatcher and shortcut catalog; its
feature switch, disabled bindings, stale combinations and conflicts are respected.

Select a region using the system picker (Screen Recording permission required).
Vision recognizes the image locally; review/edit up to 2,048 UTF-8 bytes, then
explicitly choose Search Google. Only the reviewed query goes in an HTTPS browser
search URL. No clipboard write, image upload or automatic search occurs. Existing
Lens/Bing/Yandex/TinEye placeholder preferences are not used for text search.

The picker uses one private temporary folder (0700), suppresses capture sound and
has a 60-second selection timeout. The generated image is removed after success
or failure. A cancelled job remains single-flight until its provider finishes;
late results are rejected after clearing, leaving the view, disabling, locking or
sleeping. Selection/delivery also check the active unlocked console and secure
input. Region and other media OCR now share Vision's fast recognizer with explicit
supported CPU-device selection. The accurate recognizer failed in Apple's native
runtime even with CPU selection; see the [compatibility path and accuracy/language
limits](media-tools.md#working-ocr-compatibility-path-25-october-2026). Vision itself is a
synchronous operation; cancellation discards its result after it returns.

`./scripts/test-region-text-search.sh` passes query bounds/encoding, explicit
opening, single-flight and stale-result guards, real manager/result-view/capture
adapter compilation with fake settings, and generated-image Vision recognition
with private-folder success/failure cleanup. No real desktop capture, browser
opening or general clipboard access was used by tests. The full local Mac build
passed. Actual picker/permission, shortcut and notch/browser interaction remain
attended checks. This implements text search only; visual/reverse-image Circle
to Search remains unimplemented.
