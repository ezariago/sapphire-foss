#!/usr/bin/env python3
"""Choose a stable available development signer, retaining an explicit ad-hoc option."""
import os
import re
import subprocess
import sys


def choose_identity(output, requested=None):
    identities = re.findall(r'^\s*\d+\) ([0-9A-F]{40}) "([^"]+)"', output, re.MULTILINE)
    if requested == "-":
        return "-"
    if requested:
        matches = [fingerprint for fingerprint, name in identities
                   if requested.upper() == fingerprint or requested == name]
        if len(matches) != 1:
            raise ValueError("SAPPHIRE_SIGNING_IDENTITY must name one valid code-signing identity, or '-' for ad-hoc signing.")
        return matches[0]
    development = sorted({fingerprint for fingerprint, name in identities if name.startswith("Apple Development:")})
    if len(development) == 1:
        return development[0]
    if len(development) > 1:
        raise ValueError("Multiple Apple Development identities found. Set SAPPHIRE_SIGNING_IDENTITY to the desired certificate name or SHA-1 fingerprint.")
    return "-"


def main():
    result = subprocess.run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"],
                            capture_output=True, text=True, check=True)
    identity = choose_identity(result.stdout, os.environ.get("SAPPHIRE_SIGNING_IDENTITY"))
    if identity == "-":
        print("Using ad-hoc signing; rebuilt apps may request Keychain access again.", file=sys.stderr)
    else:
        print("Using a stable local signing certificate for Keychain continuity.", file=sys.stderr)
    print(identity)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
