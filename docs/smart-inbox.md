# Smart Inbox notification detection

The public build now derives recent verification codes and selected parcel
references from notifications already admitted by Sapphire's Mac notification
filters, plus fresh accepted phone notification events. This does not grant or
request new notification access, read Mail, inspect SMS databases, fetch carrier
status or look up Amazon orders. The Mac code-only notification filter also
filters parcel inputs; disable that filter to admit ordinary parcel notifications.
Phone snapshots, muted/replayed events and disconnected bridge state are excluded.

## Implemented behavior

- The conservative English/Indonesian code heuristic requires nearby verification
  context and one unambiguous candidate: 4–8 ASCII digits, or 6–8 ASCII alphanumeric
  characters including a digit. Currency/date/grouped-number candidates are
  rejected. It can miss valid templates and cannot establish who sent a code.
- One latest code is retained for at most five minutes from its notification date.
  Future, invalid and over-age timestamps are rejected. Codes are masked in the
  Settings summary until Reveal. Copy/Dismiss and the existing notch actions are
  connected to the production monitor. Consumed-code fingerprints are bounded and
  expire; diagnostic item IDs contain random UUIDs rather than codes.
- UPS, FedEx, USPS and DHL hints plus selected identifier formats create references
  explicitly labelled **Unverified**. Format detection is not carrier validation.
  At most 30 references remain for up to 24 hours. Copy, Remove and Clear work in
  Settings. Carrier site actions open fixed official landing URLs; they do not
  submit the detected identifier. Unsupported carriers have no site action.
- State is memory-only. Input size is bounded at 8 KiB, notification replay IDs at
  256, consumed fingerprints at 128. Presentation IDs suppress repeated popovers.
  Clearing, disabling, stopping, sleep and screen-lock notifications invalidate
  queued input/copies. Locked-session checks also guard ingestion, expiry and copy;
  invalid or decreasing monotonic clocks clear state. Phone bridge reset removes
  phone-derived items.
- Copies run on the existing serialized pasteboard lane, recheck current item,
  expiry and captured clipboard revision, and mark contents with
  `org.nspasteboard.ConcealedType`. Other clipboard applications may ignore that
  marker. macOS provides no cross-process clipboard compare-and-swap; another
  process can still race the final check/write. No stronger privacy guarantee is
  claimed.

## Evidence and remaining work

`./scripts/test-smart-inbox.sh` compiles the real parser, policies and monitor
against injected settings/clock/lock status and a private named pasteboard. It
covers ambiguous/invalid codes, carrier formats, bounds, expiry, replay,
clock rollback, phone clearing, stale revisions and queued disable/re-enable
rejection. It does not touch user notifications, Mail, the general clipboard or
network. The script is included in macOS CI.

Native notification permission/database availability, actual phone mirroring,
notch and Settings interaction, OS lock/sleep delivery and browser navigation
remain unverified. The full legacy/private build is not verified. Mail scanning
is visibly disabled in the public build. Carrier APIs, automatic delivery status,
Amazon integration and broader language/template coverage remain unimplemented;
the README roadmap item therefore remains open.
