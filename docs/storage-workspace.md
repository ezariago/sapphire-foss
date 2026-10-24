# Storage workspace and notch capacity

Added 24 October 2026. The workspace uses the existing public scanner/model for
folder selection, scans/cancellation, deep duplicate hashing, filtered/sorted
file lists, category inspection, duplicate groups, capacity and issue reporting.
Ordinary directories can be opened; files, packages and symbolic links can be
revealed in Finder. No file is launched from a scan result.

Opening settings loads a recent cached index if available. A new scan requires
Scan folder, choosing a folder or directory navigation. Deep scans are optional;
changing the mode clears the previous mode's presented results and checks its
cache. Partial/cancelled/trimmed scans and inaccessible items are reported. Deep
category inspection uses the recursive insight entries; normal browsing shows
the current directory. Duplicate searches match paths, with the first 50 matching
paths shown per group. Issue lists show the first 100 with a truncation notice.

Per-item Trash actions use the existing review dialog and model policy. Protected
items are inspection-only. The model rejects out-of-scope paths and already-
trashed items, revalidates identity/type/modification metadata before moving, and
reports failures. It never permanently deletes existing Trash. Duplicate groups
do not automatically choose files to remove. Moving to Trash is not reported as
freed disk space; emptying Trash remains a separate Finder action. No personal
file was removed or trashed during implementation/tests.

The notch widget and detail view read root-volume capacity every 30 seconds only
while their SwiftUI task is active. They do not scan directory contents. Available
space includes the system's purgeable estimate; free-now and purgeable bytes are
separate in detail/settings. Shared APFS storage/snapshots can affect these values.
Unavailable readings show a loading/error state rather than a fabricated total.
The existing notch tap setting opens the capacity detail view.

`./scripts/test-storage.sh` compiles the actual scanner/model and workspace with
an explicit fixture-only flag excluding unrelated installed-app/uninstaller code.
Only the unrelated feature-access/unused Space Map dependencies are supplied by
the fixture; scanner, duplicate hashing, capacity, filtering, cancellation and
removal guards are production code. A UUID-owned cache folder and defaults domain
are created and removed. Real fixtures cover duplicate hashing, filtering/sorting,
capacity bounds, protected/out-of-scope/symlink rejection, review cancellation and
refusal after a reviewed file changes. No successful Trash operation is performed.
The non-rendering mode is included in CI.

`./scripts/test-storage.sh --render` additionally renders only the synthetic
workspace in a temporary window wholly outside every display. That image was
visually inspected locally. This checks the workspace layout, not permission
prompts, actual user input, widget placement or successful Trash/recovery behavior.
The first unattached offscreen capture did not render native labels correctly;
the fixture now uses a real offscreen window and the production scroll container.

Native folder-picker/TCC behavior, successful Trash/restore and low-disk/removable-
volume recovery still require attended checks. Interactive tree/Space Map/pie
visualizations and history/recommendation workflows remain incomplete. Monitoring
settings, adapter-power readings and menu-bar profile automation are separate
unfinished roadmap paths; these views do not implement them.
