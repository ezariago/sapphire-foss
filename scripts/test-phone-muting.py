#!/usr/bin/env python3
"""Verify Mac-only app muting with the fixed synthetic Android notification."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("pid", type=int)
parser.add_argument("--adb", default="adb")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
directory = Path(tempfile.gettempdir()) / f"sapphire-phone-diagnostics-{args.pid}"

def state():
    return json.loads((directory / "state.json").read_text())

def command(action):
    subprocess.run(["python3", str(root / "scripts/phone-diagnostics.py"), "--pid", str(args.pid), action], check=True, stdout=subprocess.DEVNULL)

def fixture(action):
    subprocess.run([args.adb, "shell", "am", "start", "-n", "dev.sapphire.companion/.NotificationFixtureActivity", "--es", "fixture", action], check=True, capture_output=True)
    time.sleep(.4)  # Let the transient fixture Activity finish before another intent.

def wait(name, predicate, seconds=35):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate(state()):
            print("PASS:", name, flush=True)
            return
        time.sleep(.2)
    raise RuntimeError("Timed out: " + name)

initial = state()
if not initial.get("isSecure"):
    parser.error("A secure paired phone connection is required.")
was_muted = initial.get("notificationFixtureMuted", False)
try:
    fixture("test-enable")
    command("notification-test-unmute")
    wait("fixture app initially allowed", lambda s: not s["notificationFixtureMuted"])
    fixture("post")
    wait("fixture arrives", lambda s: s["notificationFixtureState"] == "posted")
    command("notification-test-mute")
    wait("muting immediately clears the Mac copy and activity", lambda s:
         s["notificationFixtureMuted"] and s["notificationFixtureState"] == "absent" and not s["notificationFixtureActivityVisible"])
    phone = subprocess.run([args.adb, "shell", "cmd", "notification", "list"], check=True, capture_output=True, text=True)
    assert "|sapphire-notification-fixture|" in phone.stdout, "Muting must leave the phone notification intact"
    print("PASS: phone independently retains its notification", flush=True)
    fixture("update")
    time.sleep(3)
    assert state()["notificationFixtureState"] == "absent", "Muted updates must remain hidden"
    print("PASS: new revisions remain muted", flush=True)
    command("simulate-sleep")
    wait("sleep clears session", lambda s: s["isSleeping"] and not s["isSecure"])
    command("simulate-wake")
    wait("secure reconnect while muted", lambda s: s["isSecure"], seconds=55)
    time.sleep(3)
    assert state()["notificationFixtureState"] == "absent" and state()["notificationFixtureMuted"]
    print("PASS: reconnect snapshots respect saved muting", flush=True)
    command("notification-test-unmute")
    wait("allow restores the current revision quietly", lambda s:
         not s["notificationFixtureMuted"] and s["notificationFixtureState"] == "updated" and not s["notificationFixtureActivityVisible"])
finally:
    fixture("remove")
    fixture("test-disable")
    command("notification-test-mute" if was_muted else "notification-test-unmute")
print("Synthetic notification muting checks passed.", flush=True)
