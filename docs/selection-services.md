# Selection Services

The public build now supplies two explicit macOS Services actions, disabled by
default through **System → Selection Services**:

- **Sapphire → Clean Selected Text** returns plain text using the existing Remove
  Links, Remove Emojis and Remove List Markers settings. Those options are visible
  when either Selection Services or the separate plain-text paste shortcut is
  enabled. With no cleanup options selected, text content is preserved. The
  requesting editor controls selection replacement and its resulting style.
- **Sapphire → Remove Tracking from URL** accepts one HTTP(S) URL with no surrounding
  whitespace. It uses the existing cleaner and Clipboard custom parameter list,
  preserving encoded retained values, fragments and recognized signed URLs. It
  neither opens a browser nor requests the URL. It cannot recognize every signing
  scheme or tracking parameter; review the returned URL where that matters.

Select text in a compatible editable application and use its Services menu or
context menu. macOS may require enabling the entries under **System Settings →
Keyboard → Keyboard Shortcuts → Services** and rediscovering the installed app.
Sapphire does not change those preferences. Applications decide which Services
they offer and whether they can accept replacement text. This is not arbitrary
injection into every application's native context menu.

Only the supplied service-selection pasteboard is processed. The handler rejects
system clipboard/Find/Font/Ruler/Drag boards, multiple items, concealed/transient
markers, invalid UTF-8, NUL, empty inputs and inputs larger than 64 KiB. URL custom
parameter configuration is bounded to 256 names of at most 128 UTF-8 bytes each.
Configuration and revision are rechecked after materializing promised data. The
result is prepared before replacing the selection board; a write failure returns
an error to the requesting app. There is no cross-process atomic clipboard
transaction. Materializing a promised representation is controlled by its source;
its allocation happens before the returned data's size can be checked.

The Services provider does not read/write the general clipboard, send synthetic
keys, request Accessibility, access the network or parse rich-text/HTML documents.
The requesting app supplies its plain-text selection representation. Returning
plain text cannot guarantee removal of styling inherited by the host editor.
No selected text is logged or persisted by this handler.

The public build helper generates a public Info.plist advertising only the two
implemented Services selectors; it omits the previously advertised no-op photo
and scanning Services. The upstream Info.plist is retained for private builds.
One provider owns these selectors, and the public Continuity registration delegates
to it instead of replacing it with another provider.

## Verification

`./scripts/test-selection-services.sh` compiles the actual service provider,
shared sanitizer and URL policy. A unique named pasteboard exercises real
Objective-C selectors, replacement/refusal, marker/multiple-item/encoding/limit
checks, Unicode preservation, selected cleanup, encoded/signed URLs and stale
configuration/revision rejection. Selectors and types are checked against the
public Services plist. The test leaves the general clipboard, user selections,
Services registry and other apps untouched. It runs in macOS CI.

Native Services discovery/enabling, menu delivery, replacement and inherited
style in third-party editors remain manual checks. Full private-build service
registration is unverified. This implements a defined subset of the README's
context-menu enhancement work; it does not establish full upstream parity.

Registration follows Apple's [Services properties](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html)
and [selection exchange model](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/using.html).
