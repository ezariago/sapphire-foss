# Automatic clipboard and copied-link prompts

Android Companion → Features → Clipboard has an **Automatically send phone
clipboard** switch (off by default). While Companion has focus, a clipboard
listener sends new plain text over the existing authenticated BLE connection;
returning to Companion also offers the latest copy once per timestamp/digest.
Sensitive copies, Mac-origin copies, multiple items, URI-only content, empty/NUL
text and text at or above 12,000 UTF-8 bytes are skipped. The Mac now automatically
writes accepted phone text when Continuity clipboard sync is enabled. Its remote
pasteboard marker and Android's Mac-origin marker prevent echoes. Disabling
automatic Mac delivery leaves the received-text review/copy control available.

## Background Android sending

Android ordinarily permits clipboard reading only to the focused app or default
keyboard. The optional existing Sapphire Helper has a new clipboard broker using
authorized Shizuku shell access; no keyboard replacement is needed. It is off by
default in both apps. Install the matching Helper, start/authorize Shizuku, turn
on **Allow background clipboard for Sapphire** in Helper, and enable both phone
clipboard switches in Companion. **Retry background clipboard** refreshes setup;
the status distinguishes ready from missing permission. Shizuku may need to be
started again after reboot. Root mode and unsupported hidden API signatures fail
closed. Current implementation targets Android's owner/current-user clipboard,
not work-profile or cross-device clipboard routing.

The fixed helper component is signature-protected. Its narrow interface registers
a read-only clipboard-change callback; it accepts no commands, arbitrary service
names, URI reads or clipboard writes. It reads new changes only after explicit
activation, while the phone is unlocked. Text is filtered before leaving Helper.
The Companion rechecks connection and switches before sending. The listener
clears on disconnect, service death, helper opt-out or loss of authorization.
Only a timestamp/digest deduplication record remains in memory; no helper history
is stored. Multiple changes are coalesced and only one native read runs at once.

Android sources: [clipboard restrictions](https://source.android.com/docs/security/enhancements),
[shell background-read permission](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/packages/Shell/AndroidManifest.xml),
and [clipboard Binder interface](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android16-release/core/java/android/content/IClipboard.aidl).

## Copied links

When receive-clipboard and link handoff are enabled on Android, a Mac text copy
containing an HTTP(S) link offers **Open copied link from Mac?** for about five
seconds. It uses a separate high-importance, private, silent channel with a
5,000 ms timeout. Android/OEM notification policy controls heads-up visibility
and exact timing. Tapping leads to URL review and a separate browser-open click;
nothing opens automatically. A received phone copy with a safe web link offers
a compact Mac notch prompt with **Open**/**Dismiss** for five seconds. The host
is shown; the full URL is available on hover. A click rechecks identity, expiry,
connection, settings and unlocked console. Higher-priority activities, lock and
full-screen policy can suppress it; expired prompts are not replayed.

Only the first valid HTTP(S) candidate in bounded text is offered; punctuation
and unmatched closing brackets are trimmed, credentials/custom/file schemes
are rejected. New prompts replace old ones, and disconnect clears pending state.
Existing explicit Share/manual link handoff remains available.

## Verification

Mac protocol/extraction/expiry and isolated marked pasteboard tests passed, as
did shortcut, media and file-harness regressions. The full local Mac build,
Android JVM tests, Companion/Helper debug and release builds and debug lint pass.
The earlier storage repair also passed its full hosted CI run.

The original lock-screen blocker was resolved in the next attended check. The
production helper read a fixed synthetic copy while its test app was out of focus,
and cleanup restored the opaque original clipboard and original helper switch.
The launcher now creates distinct fixture tasks: Android had reused the first
window, preventing its initial restore request from being handled.

The subsequent live relay check passed with the phone launcher in front and
neither Companion nor Helper holding window focus:

- Production helper → normal Companion client → authenticated BLE → a marked,
  private Mac pasteboard, with the expected bytes only.
- Actual live-activity manager selection and five-second expiry of the compact
  copied-link prompt, with no browser opening.
- Sensitive and Mac-origin synthetic copies skipped without relay or a prompt.
- A later fresh copy of identical text relayed again.
- Helper opt-out propagated to Companion, then access recovered automatically
  after the bounded retry delay, with no existing-clipboard replay.

The Companion and Helper preference snapshots and phone clipboard were restored
only for the owned run; the Mac general clipboard was not used for assertions or
fixture delivery. Normal Mac startup was restored and its private diagnostic
files removed. Afterward the requested normal clipboard switches and Helper
access were enabled; receive-links was already enabled. No phone sleep command
is sent by the new relay test or the updated standalone helper test. A debug-only
timed wake lock holds the screen during the synthetic session (at most ten
minutes), then releases without changing persistent wake/alarm settings.

Evidence: `build/background-clipboard-helper-live.log`,
`build/clipboard-relay-recovery-live.log`, `build/clipboard-relay-android-build.log`,
and `build/clipboard-recovery-android-build.log`. Both Android apps' debug/release
builds, debug lint, all 26 JVM cases and the full local Mac build passed.
Shizuku process death/reboot and work-profile/OEM variations still need their own
checks. Actual browser-open clicks and visual heads-up/notch appearance remain
manual interaction checks; activity selection is not a visual audit.

A separate notification-only native probe passed while the phone was locked. It
called production copied-text handoff using a fixed `example.com` link, verified
private visibility, a non-null review intent and 5,000 ms timeout, then observed
Android remove the notification by six seconds. It restored the original handoff
preference and never touched clipboard contents or opened a browser. This proves
notification construction/expiry, not unlocked heads-up presentation or tap flow.
Both debug fixtures are absent from release manifests. Companion 0.6.0 and Helper
0.2.0 were installed in place with matching existing debug certificates and retained
app data. Android blocked an external direct start of the non-exported link service;
it was kept private. Reopen Companion/Start connection after unlocking as needed.

## Automatic retry

While the secure link and both sending switches remain enabled, missing or stale
helper bindings and unavailable authorization retry at a bounded 30-second
interval. Ready bindings do not churn. Helper opt-out explicitly reports disabled
before removing the listener, and disabling sending cancels/rejects callbacks
immediately. The manual Retry control checks setup without waiting for the timer.
Recovery registers for new copies; it does not replay the current clipboard.
