#!/usr/bin/env python3
"""Exercise only the fixed debug Android notification fixture over the real encrypted link."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("pid", type=int, help="Mac Sapphire PID launched with --phone-diagnostics")
parser.add_argument("--dismiss-only", action="store_true", help="Only test dismissal/removal; no replies, actions or sleep/wake")
parser.add_argument("--adb", default=str(Path.home() / "Library/Android/sdk/platform-tools/adb"))
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
directory = Path(tempfile.gettempdir()) / f"sapphire-phone-diagnostics-{args.pid}"


def state():
    # Read only readiness and the fixed fixture state; never print other phone data.
    return json.loads((directory / "state.json").read_text())


def wait(name, predicate, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate(state()):
            print("PASS:", name, flush=True)
            return
        time.sleep(0.2)
    raise RuntimeError("Timed out: " + name)


def command(action):
    subprocess.run(["python3", str(root / "scripts/phone-diagnostics.py"), "--pid", str(args.pid), action],
                   check=True, stdout=subprocess.DEVNULL)


def fixture(action):
    subprocess.run([args.adb, "shell", "am", "start", "--user", "0", "-n",
                    "dev.sapphire.companion/.NotificationFixtureActivity", "--es", "fixture", action],
                   check=True, capture_output=True)


def fixture_flag(name):
    result = subprocess.run([args.adb, "shell", "run-as", "dev.sapphire.companion", "cat",
                             "shared_prefs/notification-fixture.xml"], capture_output=True, text=True, check=True)
    return any(e.get("name") == name and e.get("value") == "true" for e in ET.fromstring(result.stdout))


device = subprocess.run([args.adb, "get-state"], capture_output=True, text=True)
if device.returncode != 0 or device.stdout.strip() != "device":
    parser.error("ADB device unavailable. Connect the debug companion phone by USB before running the device checks.")

if not state().get("isSecure"):
    parser.error("Connect the paired companion securely and grant notification access/sharing first.")
if args.dismiss_only:
    try:
        fixture("post")
        wait("fixture arrives in the visible Mac activity", lambda s:
             s.get("notificationFixtureState") == "posted" and s.get("notificationFixtureActivityVisible"))
        command("notification-test-dismiss")
        wait("Mac entry and visible activity close", lambda s:
             s.get("notificationFixtureState") == "absent" and not s.get("notificationFixtureActivityVisible"))
        def phone_fixture_removed(_):
            result = subprocess.run([args.adb, "shell", "cmd", "notification", "list"],
                                    capture_output=True, text=True, check=True)
            return "|sapphire-notification-fixture|" not in result.stdout
        wait("phone independently confirms fixture cancellation", phone_fixture_removed)
        fixture("post")
        wait("a new fixture revision appears", lambda s:
             s.get("notificationFixtureState") == "posted" and s.get("notificationFixtureActivityVisible"))
        fixture("remove")
        wait("phone removal also closes the Mac activity", lambda s:
             s.get("notificationFixtureState") == "absent" and not s.get("notificationFixtureActivityVisible"))
    finally:
        fixture("remove")
    print("Synthetic dismissal device checks passed.", flush=True)
    raise SystemExit(0)

try:
    fixture("post")
    wait("encrypted notification arrival in the notch", lambda s:
         s.get("notificationFixtureState") == "posted" and s.get("notificationFixtureActivityVisible"))
    fixture("update")
    wait("notification update replaces fixture", lambda s: s.get("notificationFixtureState") == "updated")
    command("notification-test-action")
    wait("Mac action reaches Android PendingIntent", lambda s: s.get("notificationFixtureState") == "action-verified")
    assert fixture_flag("actionVerified"), "Android action receiver did not confirm"
    command("notification-test-reply")
    wait("Mac reply reaches Android RemoteInput", lambda s: s.get("notificationFixtureState") == "reply-verified")
    assert fixture_flag("replyVerified"), "Android reply receiver did not confirm"
    command("notification-test-dismiss")
    wait("Mac dismissal removes entry and visible notch activity", lambda s:
         s.get("notificationFixtureState") == "absent" and not s.get("notificationFixtureActivityVisible"))
    fixture("post")
    wait("fixture repost", lambda s: s.get("notificationFixtureState") == "posted")
    fixture("remove")
    wait("phone removal clears Mac notification and visible notch activity", lambda s:
         s.get("notificationFixtureState") == "absent" and not s.get("notificationFixtureActivityVisible"))
    fixture("post")
    wait("fixture before reconnect", lambda s: s.get("notificationFixtureState") == "posted")
    command("simulate-sleep")
    wait("disconnect clears mirrored content", lambda s: s.get("isSleeping") and not s.get("isSecure")
         and s.get("phoneNotificationCount") == 0)
    command("simulate-wake")
    wait("reconnect silently restores active fixture", lambda s: s.get("isSecure")
         and s.get("notificationFixtureState") == "posted" and not s.get("hasPhoneNotificationAlert"), seconds=45)
finally:
    # Leave transport recovery enabled even if a lifecycle assertion fails.
    if state().get("isSleeping"):
        command("simulate-wake")
    # Remove only our disposable synthetic notification, even after an assertion fails.
    fixture("remove")
print("Synthetic notification device checks passed. No real messages were sent.", flush=True)
