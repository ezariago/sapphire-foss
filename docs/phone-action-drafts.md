# Android SMS and dialer drafts

This is a first implementation of the Mac-to-phone action bridge, not full SMS
or call synchronization. The Mac can prepare an SMS draft or dialer number over
the authenticated BLE session. The phone must advertise support, enable Receive
SMS and dialer drafts and allow Sapphire notifications. Draft receiving is disabled by default.
The ordinary message/call manager placeholders are not replaced by inbox sync.

A private notification contains no recipient/message preview. On an unlocked
phone, the user reviews the number and text in a non-exported Sapphire activity,
then explicitly opens Android's SMS composer (`ACTION_SENDTO`, `smsto:`) or dialer
(`ACTION_DIAL`, `tel:`). Sapphire never invokes `ACTION_CALL`, sends an SMS,
answers/hangs up a call or reads contacts, SMS/call history. Sending/calling stays
with the system app and its user action; carrier/SIM behavior is unverified.

Only 7–15 ASCII digits with an optional leading plus are accepted. URI input,
service/short codes, extensions, pauses and non-ASCII numbers are rejected. SMS
bodies are capped at 4,000 UTF-8 bytes; invalid UTF-16, NUL and controls other than
tab/line breaks are rejected. There is no automatic retry. The Mac matches the
result to its pending request and times out after 15 seconds; Ready confirms a
review notification, never a delivered SMS or connected call.

One in-memory phone draft replaces the previous one. A random immutable review
token binds the non-exported activity to the current secure service connection.
Drafts expire after two minutes, consume once and are invalidated on replacement,
disconnect, stop, feature disable or clock rollback. Recent request IDs are
bounded/deduplicated. Late/stale activities revalidate before opening a system
app. Recipient/body are not persisted in preferences, diagnostics or notification
PendingIntent extras. Closing Mac settings clears its local input fields.

Verification:

- Mac policy/protocol fixtures cover number/body bounds and plaintext rejection;
  the independent Java cryptography fixtures remain part of that suite.
- Android JVM tests cover validation, expiry, replay/replacement, one-shot review
  and bounded ID retention. App/helper debug APKs build successfully.
- The new separate `dev.sapphire.fixture` APK compiles selected production policy,
  intent, crypto and framing sources. On the user's USB Samsung it verified real
  Android intent construction, ECDH/ChaCha providers, replay rejection and framing.
  It launched no external activity and read no user/companion data. It was removed
  afterward, and the phone reported Dozing with stay-on disabled.

The production notification/review UI, phone-side opt-in, encrypted draft request/
reply across two running apps, missing-handler/lockscreen behavior and system
composer/dialer presentation remain attended checks. No SMS, call or third-party
contact was used for tests. The installed companion was not replaced by the
isolated fixture; install the newly built companion APK before trying this path.
Full inbox/conversation synchronization, message delivery reporting, incoming
call UI/audio and remote call controls remain on the roadmap.
