#!/usr/bin/env python3
"""Test fixed public URL handoff over the encrypted link, without opening a browser."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

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
    subprocess.run([args.adb, "shell", "am", "start", "-W", "-n", "dev.sapphire.companion/.HandoffFixtureActivity", "--es", "fixture", action], check=True, capture_output=True)
    time.sleep(.4)

def wait(name, predicate, seconds=30):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate(state()):
            print("PASS:", name, flush=True)
            return
        time.sleep(.2)
    raise RuntimeError("Timed out: " + name)

if not state().get("isSecure"):
    parser.error("A secure paired phone connection is required.")
prefs = subprocess.run([args.adb, "shell", "run-as", "dev.sapphire.companion", "cat", "shared_prefs/settings.xml"], capture_output=True, text=True, check=True)
was_enabled = any(e.get("name") == "handoff" and e.get("value") == "true" for e in ET.fromstring(prefs.stdout))
try:
    fixture("disable")
    command("handoff-test-send")
    wait("phone rejects handoff while disabled", lambda s: s["handoffState"] == "disabled")
    fixture("enable")
    command("handoff-test-send")
    wait("phone acknowledges a review notification", lambda s: s["handoffState"] == "ready")
    phone = subprocess.run([args.adb, "shell", "cmd", "notification", "list"], capture_output=True, text=True, check=True)
    assert "|sapphire-link-handoff|" in phone.stdout
    print("PASS: phone independently shows the handoff notification", flush=True)
    fixture("review")
    # This opens the app's review screen only, never the browser or URL itself.
    result = subprocess.run([args.adb, "shell", "dumpsys", "activity", "activities"], capture_output=True, text=True, check=True)
    assert "dev.sapphire.companion/.ReceivedLinkActivity" in result.stdout
    print("PASS: tapping the notification opens the phone review screen", flush=True)
    fixture("send")
    wait("phone-to-Mac fixed URL arrives", lambda s: s["handoffFixtureReceived"])
finally:
    fixture("remove")
    fixture("enable" if was_enabled else "disable")
print("Bidirectional link handoff device checks passed; no browser was opened.", flush=True)
