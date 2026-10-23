#!/usr/bin/env python3
"""Record pinned source and bundled opaque inputs without guessing their licenses."""
import argparse
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]

def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()

def inventory():
    resolved = ROOT / 'Sapphire.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
    packages = []
    checkouts = ROOT / 'build/DerivedData/SourcePackages/checkouts'
    for pin in json.loads(resolved.read_text())['pins']:
        checkout = checkouts / pin['identity']
        licenses = []
        if checkout.is_dir():
            for path in sorted(checkout.iterdir()):
                if path.is_file() and path.name.lower().startswith(('license', 'copying', 'notice')):
                    licenses.append({'file': path.name, 'sha256': sha256(path)})
        packages.append({'identity': pin['identity'], 'source': pin['location'],
                         **pin['state'], 'license_evidence': licenses,
                         'license_review': 'required; evidence is not a license classification'})
    opaque = []
    paths = [ROOT / 'Sapphire/Services/Music/MediaRemoteAdapter.framework',
             ROOT / 'Sapphire/Services/Music/SapphireMediaQueue.framework',
             ROOT / 'Sapphire/Services/FaceID/Models']
    for directory in paths:
        for path in sorted(directory.rglob('*')):
            if path.is_file() and not path.is_symlink():
                opaque.append({'path': str(path.relative_to(ROOT)), 'bytes': path.stat().st_size,
                               'sha256': sha256(path), 'provenance': 'unverified inherited artifact'})
    return {'schema': 1, 'package_resolved_sha256': sha256(resolved),
            'packages': packages, 'opaque_inputs': opaque}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path)
    args = parser.parse_args()
    result = json.dumps(inventory(), indent=2) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(result)
    else:
        print(result, end='')
