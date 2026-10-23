#!/bin/bash
set -euo pipefail

SAPPHIRE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SAPPHIRE_ROOT"

# Avoid stalled HTTP/2 GitHub transfers on this connection. Scope this to the build.
for SAPPHIRE_GIT_OPTION in http.version=HTTP/1.1 http.lowSpeedLimit=1024 http.lowSpeedTime=45; do
    SAPPHIRE_GIT_CONFIG_INDEX="${GIT_CONFIG_COUNT:-0}"
    export "GIT_CONFIG_KEY_${SAPPHIRE_GIT_CONFIG_INDEX}=${SAPPHIRE_GIT_OPTION%%=*}"
    export "GIT_CONFIG_VALUE_${SAPPHIRE_GIT_CONFIG_INDEX}=${SAPPHIRE_GIT_OPTION#*=}"
    export GIT_CONFIG_COUNT="$((SAPPHIRE_GIT_CONFIG_INDEX + 1))"
done
export SWIFTPM_MAX_CONCURRENT_OPERATIONS="${SWIFTPM_MAX_CONCURRENT_OPERATIONS:-2}"

# Optional GitHub SSH transport for connections where HTTPS downloads stall.
# Uses the user's existing GitHub SSH authentication and a task-local host file.
if [[ "${SAPPHIRE_GITHUB_SSH:-0}" == 1 ]]; then
    mkdir -p build
    echo '[ssh.github.com]:443 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' > build/github-known-hosts
    export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile='$SAPPHIRE_ROOT/build/github-known-hosts' -o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3"
    SAPPHIRE_GIT_CONFIG_INDEX="${GIT_CONFIG_COUNT:-0}"
    export "GIT_CONFIG_KEY_${SAPPHIRE_GIT_CONFIG_INDEX}=url.ssh://git@ssh.github.com:443/.insteadOf"
    export "GIT_CONFIG_VALUE_${SAPPHIRE_GIT_CONFIG_INDEX}=https://github.com/"
    export GIT_CONFIG_COUNT="$((SAPPHIRE_GIT_CONFIG_INDEX + 1))"
fi

# Use an installed Xcode without changing the system-wide developer selection.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
    echo "Full Xcode is required. Install Xcode, open it once, and complete its setup." >&2
    echo "Then run: ./scripts/build-local.sh" >&2
    exit 1
fi

# Xcode's intermediate products remain ad-hoc signed. Apply the same stable
# identity to the final app on every build so Keychain can recognize updates.
SAPPHIRE_LOCAL_SIGNER="$(python3 scripts/local-signing-identity.py)"
python3 scripts/prepare-local-build.py
mkdir -p build/logs
SAPPHIRE_PROJECT="$SAPPHIRE_ROOT/build/Local/Sapphire.xcodeproj"
SAPPHIRE_DERIVED="$SAPPHIRE_ROOT/build/DerivedData"

: > build/logs/resolve.log
for SAPPHIRE_RESOLVE_ATTEMPT in 1 2 3; do
    echo "Dependency download attempt $SAPPHIRE_RESOLVE_ATTEMPT of 3" | tee -a build/logs/resolve.log
    if /usr/bin/xcodebuild \
        -resolvePackageDependencies \
        -project "$SAPPHIRE_PROJECT" \
        -scheme Sapphire \
        -derivedDataPath "$SAPPHIRE_DERIVED" \
        -onlyUsePackageVersionsFromResolvedFile \
        2>&1 | tee -a build/logs/resolve.log; then
        break
    fi
    if [[ "$SAPPHIRE_RESOLVE_ATTEMPT" == 3 ]]; then
        echo "Dependency downloads failed. See build/logs/resolve.log." >&2
        exit 1
    fi
done

/usr/bin/xcodebuild \
    -project "$SAPPHIRE_PROJECT" \
    -scheme Sapphire \
    -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$SAPPHIRE_DERIVED" \
    -disableAutomaticPackageResolution \
    ONLY_ACTIVE_ARCH=YES \
    build \
    2>&1 | tee build/logs/build.log

SAPPHIRE_APP="$SAPPHIRE_DERIVED/Build/Products/Release/Sapphire.app"
test -x "$SAPPHIRE_APP/Contents/MacOS/Sapphire"
# These helpers are loaded from Resources at runtime rather than linked at launch.
for SAPPHIRE_FRAMEWORK in MediaRemoteAdapter SapphireMediaQueue; do
    /usr/bin/ditto \
        "Sapphire/Services/Music/$SAPPHIRE_FRAMEWORK.framework" \
        "$SAPPHIRE_APP/Contents/Resources/$SAPPHIRE_FRAMEWORK.framework"
    /usr/bin/codesign --force --sign "$SAPPHIRE_LOCAL_SIGNER" --timestamp=none \
        "$SAPPHIRE_APP/Contents/Resources/$SAPPHIRE_FRAMEWORK.framework"
done
for SAPPHIRE_SCRIPT in mediaremote-adapter.pl mediaremote-queue.pl; do
    /usr/bin/ditto "Sapphire/Services/Music/$SAPPHIRE_SCRIPT" \
        "$SAPPHIRE_APP/Contents/Resources/$SAPPHIRE_SCRIPT"
done
/usr/bin/codesign --force --sign "$SAPPHIRE_LOCAL_SIGNER" --timestamp=none --options runtime \
    --entitlements "$SAPPHIRE_ROOT/build/Local/Local.entitlements" "$SAPPHIRE_APP"
/usr/bin/codesign --verify --deep --strict "$SAPPHIRE_APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$SAPPHIRE_APP" build/Sapphire-local.zip
echo "Built: $SAPPHIRE_APP"
echo "Zip:   $SAPPHIRE_ROOT/build/Sapphire-local.zip"
echo "Quit any running Sapphire, then open the app above."
