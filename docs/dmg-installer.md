# Public disk-image installer

Implemented 2026-10-24. Enable it in Archives & DMG; it is disabled by default.
Open a DMG through the app or explicitly choose Sapphire as the default handler.
When disabled, DMGs are forwarded to Apple's DiskImageMounter.

Images mount read-only, without auto-opening Finder, under a fresh temporary
mount root. Only top-level `.app` bundles are offered. Package installers,
encrypted images requiring a password and unsigned applications can be opened
with DiskImageMounter instead. No package scripts or image-provided programs run
as part of mounting or copying.

The installer validates source and staged app signatures and preserves the
image's quarantine on staged contents. It creates a new stage beside the final
app before moving anything into place. Replacements require the installed app's
publisher requirement, a matching bundle/signing identity and a non-running app.
The existing application is retained as a hidden `.Sapphire-backup-….app` beside
the replacement. A failed final move attempts restoration; retained backups can
be recovered in Finder with Show Hidden Files. No privileged helper or password
is used to obtain write access; select ~/Applications if /Applications is not
writable. Signature validation does not replace Gatekeeper/notarization checks.

New installations and replacements normally ask for confirmation. The existing
replacement-without-prompt preference applies only to replacements that satisfy
all signature checks. Downloaded DMGs are trashed only after every selected app
has installed and the image detached successfully, if that option is enabled.

`./scripts/test-dmg-installer.sh` generates a signed fixture app and real DMG. It
passed read-only mount/discovery, install/stage signature verification, duplicate
rejection, replacement backup, tampered/symlink-source rejection and detach. Tests
install only into a temporary directory, never /Applications. Real default-handler
permission prompts, Gatekeeper launch behavior, disk-full/permissions failure,
multi-volume images and manual-mount offering remain separate device checks.
