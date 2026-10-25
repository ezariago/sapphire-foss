# Native compression and local OCR

Added 2026-10-24. File Shelf actions and Media Optimizer settings use native macOS
frameworks. Compression always produces a separate copy beside the source. A
failed export or a result that is not smaller is removed; the original stays
unchanged. Quarantine is retained on output files.

Images are resized with orientation correction and encoded as JPEG or PNG when
an alpha channel is present. Animated/multipage image optimization is rejected
rather than silently dropping frames/pages. Image quality and maximum dimension
are configurable. PDF compression uses PDFKit's image optimization/JPEG options;
see [Apple's PDFKit options](https://developer.apple.com/documentation/pdfkit/pdfdocumentwriteoption).
Encrypted PDFs are rejected instead of silently removing their protection.
Compression is lossy and is intended for screen viewing, not archival masters.
Video uses AVFoundation's medium-quality MP4 export and audio uses M4A export;
unsupported native formats report an error.

OCR uses Vision’s fast recognizer with explicit supported CPU-device assignments
on this Mac. Image text and scanned PDF pages are recognized;
existing PDF text is retained in the extraction result. PDF OCR is bounded to
100 pages. File selection and a configurable screenshot-region shortcut are
available in Media Optimizer settings. Interactive screen capture uses the
system selector and requires Screen Recording permission; Escape cancels. The
region image is written to a temporary PNG and removed after recognition; an
interrupted app/process can leave that temporary image until system cleanup.

Automatic screenshot monitoring is disabled by default. When enabled it watches
new images in the system screenshot folder and reads only files whose Spotlight
metadata confirms they are screenshots. Existing images are ignored. Indexing
may delay detection; screenshots in unindexed folders will not be processed.
Recognized text remains in memory until cleared or the app quits. Automatic copy
is a separate opt-in; clipboard sharing can forward that text to the paired phone.

`./scripts/test-media-tools.sh` passed image compression/dimension/source-byte
preservation, image/PDF OCR, PDF writing and silent audio compression fixtures.
No audio was played. Actual video codecs, Screen Recording denial/approval,
interactive region selection, Spotlight screenshot detection and full UI actions
remain manual checks. Image-based Circle to Search remains unimplemented.

## Automatic clipboard image optimization

The existing opt-in preference now processes newly copied single PNG/TIFF-only
items. Encoding runs serially off the main actor, transforms orientation,
retains alpha and outputs PNG only when it is smaller. PNG encoding is lossless,
but resizing can discard detail: the configured maximum dimension is capped at
4096 px for this automatic path. Inputs are bounded to 32 MiB of representations
and 20 million pixels. Animated/multipage images are rejected. Original files
are never opened or changed by this clipboard path, and enabling does not process
the current clipboard. The file image-quality slider applies to file exports.

Unknown/rich/marked types, multiple items, secure input and unknown/nonregular or
ignored foreground apps are skipped. Pending work is invalidated by new copies,
configuration changes, app activation changes, sleep, screen lock and shutdown.
The serialized write lane rechecks the captured revision, representations and
configuration before replacement. A marker prevents optimizing its own output.
macOS has no atomic compare-and-swap across pasteboard clients: a very narrow
external-copy/configuration race remains between the final check and write.
Restoration after a failed write is attempted only for our still-empty revision.
History and other apps may see the original before the asynchronous replacement;
this does not retroactively rewrite existing history entries.

`./scripts/test-clipboard-image-optimization.sh` uses real ImageIO and a unique
named pasteboard, leaving the general clipboard untouched. It verifies PNG/TIFF
capture, native resize/alpha/savings, invalid/oversized/multipage rejection, rich/
concealed/multi-item bypass, stale revision/configuration rejection and marker
recursion prevention. Full builds check manager lifecycle wiring. Actual copying/
pasting across apps, privacy/input transitions and coexistence with clipboard
history/sharing/clearing remain native checks. No user image was read for tests.

## Region text search

A separate opt-in now implements local region OCR, editable query review and
explicit Google text search. It does not upload images or implement visual
Circle to Search. See [scope and verification](region-text-search.md). Policy,
native compilation/generated-image fixtures and a full local build passed;
real screen selection, permissions and browser interaction remain unverified.

## Current regression blocker (25 October 2026)

A rerun with generated fixtures reaches image compression, then fails during
**image OCR** with `TextRecognition.CRImageReaderError` code 1 and the Apple
runtime’s `e5rt_execution_stream_operation_create_precompiled_compute_operation_with_options`
error 13. The fixture now reports its phase and error domain/code (and underlying
error metadata when supplied), so this failure is no longer ambiguous with PDF
or audio export. This is diagnostic coverage, not an OCR repair. Later media
stages and the consolidated regression remain unverified in this run.

## Working OCR compatibility path (25 October 2026)

The failure above also reproduced with the deprecated CPU-only flag, explicit
CPU assignment and recognition revision 2. The accurate engine failed for the
region fixture after a long delay as well. Changing to Vision’s fast recognizer
with explicit per-stage supported CPU selection passed the generated image,
scanned PDF and region fixtures. All local OCR entry points now share that path;
there is no retry into the failing accurate engine. Empty/missing CPU capabilities
fail explicitly. Cancellation is checked before decoding/recognition and after
native recognition; it cannot interrupt a synchronous native request in progress.

This is a compatibility workaround, not a repair of Apple’s accurate engine.
Apple documents the [speed/accuracy tradeoff](https://developer.apple.com/documentation/vision/vnrecognizetextrequest/recognitionlevel).
Small or complex text may be missed, and language coverage is narrower. The
runtime reports en-US, fr-FR, it-IT, de-DE, es-ES and pt-BR on this Mac. Unsupported
choices report the available languages instead of silently using another one.
Settings explain the tradeoff. File Shelf, file selection and screenshot processing
now distinguish a recognition error from a successful empty result. Existing
selectable PDF text is retained without OCR, even with an unsupported recognition
language selected.

Generated fixtures pass image/PDF OCR, existing accented PDF text retention,
source-byte preservation, unsupported-language refusal, cancellation, blank-image
empty success, PDF export
and silent audio export. The region fixture also passes private temporary-directory
permissions and cleanup. No user files, screenshots, general clipboard, browser
or phone were used. All 31 shell checks configured in macOS CI plus the isolated
file-transfer harness passed locally (32 checks); the expanded media fixture was
also rerun successfully. This supersedes the earlier failed consolidated run.
The full local app build, signature verification and ZIP packaging also passed.
Higher-accuracy/multilingual OCR and
attended UI interactions remain open.
