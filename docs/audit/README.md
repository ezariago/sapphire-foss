# Dependency and build provenance audit

Initial inventory: 2026-10-24. Recreate with:

```sh
python3 scripts/dependency-inventory.py --output build/dependency-inventory.json
```

The machine-readable inventory records every pinned Swift package source/revision,
root license/notice file hashes from available checkouts, and exact bytes/hashes of
inherited media frameworks and Face ID model artifacts. Resolve packages first to
include their license evidence. This is an inventory, not a completed license audit.
The app's AGPL license does not establish provenance for these separate inputs.

## Remaining source and license blockers

| Input | Evidence in this checkout | Required work |
| --- | --- | --- |
| MediaRemoteAdapter.framework | Compiled Mach-O and a Perl loader carrying a BSD-3-Clause attribution to Jonas van den Berg | Identify the exact upstream source revision and license, retain full notices, build the framework from source and compare behavior |
| SapphireMediaQueue.framework | Compiled Mach-O and `mediaremote-queue.pl`; loader mentions `SapphireMediaQueue.m`, which is absent | Recover a licensed source release or implement and test a source replacement |
| ArcFace.mlpackage | Serialized model and weights, no training/source provenance supplied | Establish model/weight license and reproducible conversion or replace camera authentication |
| PassiveLiveness_v4_ANE.mlmodelc | Compiled model/weights, no training/source provenance supplied | Establish source/license and reproducible compilation or replace camera authentication |
| Swift package graph | Exact revisions in Package.resolved; several Google dependencies distribute binaries | Review transitive licenses, binary targets, notices and build provenance individually |
| System private interfaces | PrivateHeaders and runtime MediaRemote use | Document supported macOS behavior and failure recovery; system frameworks are supplied by macOS |

No claim of fully reproducible, source-only or audited FOSS binaries is made.
CI uploads the inventory with each build so shipped inputs remain inspectable.
Replacing opaque inputs must preserve media and authentication behavior; empty
frameworks or permissive authentication would not complete this checklist item.
