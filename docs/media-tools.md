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

OCR uses Vision on this Mac. Image text and scanned PDF pages are recognized;
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
remain manual checks. Automatic clipboard optimization and Circle to Search
remain on the roadmap.
