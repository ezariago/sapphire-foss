#!/usr/bin/env python3
"""Exercise the real encrypted media link using a silent debug-only Android session."""
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
    subprocess.run([args.adb, "shell", "am", "start", "-n", "dev.sapphire.companion/.MediaFixtureActivity", "--es", "fixture", action], check=True, capture_output=True)
    time.sleep(.4)  # Let the transient fixture Activity finish before another intent.

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
was_enabled = any(e.get("name") == "media" and e.get("value") == "true" for e in ET.fromstring(prefs.stdout))
try:
    fixture("enable")
    fixture("post")
    wait("silent phone session arrives on Mac", lambda s: s["mediaFixturePresent"] and not s["mediaFixturePlaying"])
    command("media-test-play")
    wait("Mac play reaches phone session", lambda s: s["mediaFixturePlaying"])
    command("media-test-pause")
    wait("Mac pause reaches phone session", lambda s: s["mediaFixturePresent"] and not s["mediaFixturePlaying"])
    command("media-test-next")
    wait("Mac next changes the synthetic track", lambda s: s["mediaFixtureTrack"] == 2)
    command("media-test-previous")
    wait("Mac previous restores the synthetic track", lambda s: s["mediaFixtureTrack"] == 1)
    command("media-test-seek")
    wait("Mac seek reaches the exact phone position", lambda s: s["mediaFixturePositionMs"] == 42000)
    command("media-test-toggle")
    wait("Mac toggle resumes the silent session", lambda s: s["mediaFixturePlaying"])
    command("media-test-stop")
    wait("Mac stop resets the silent session", lambda s: s["mediaFixturePresent"] and not s["mediaFixturePlaying"] and s["mediaFixturePositionMs"] == 0)
    fixture("disable")
    wait("turning off sharing clears Mac media", lambda s: not s["mediaFixturePresent"])
    command("media-test-play")
    time.sleep(3)
    assert not state()["mediaFixturePresent"]
    print("PASS: disabled sharing rejects remote playback", flush=True)
    fixture("enable")
    wait("reenabling sharing restores the session", lambda s: s["mediaFixturePresent"])
    fixture("remove")
    wait("phone session release clears the Mac", lambda s: not s["mediaFixturePresent"])
finally:
    fixture("remove")
    fixture("enable" if was_enabled else "disable")
print("Silent media device checks passed; no real audio played.", flush=True)
