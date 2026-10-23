#!/usr/bin/env python3
"""Cycle Android Bluetooth and verify authenticated recovery without restarting Sapphire."""
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
directory = Path(tempfile.gettempdir()) / f"sapphire-phone-diagnostics-{args.pid}"

def state():
    return json.loads((directory / "state.json").read_text())

def wait(name, predicate, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if predicate(state()):
            print("PASS:", name, flush=True)
            return
        time.sleep(.3)
    raise RuntimeError("Timed out: " + name)

def radio(enabled):
    subprocess.run([args.adb, "shell", "cmd", "bluetooth_manager", "enable" if enabled else "disable"], check=True, capture_output=True)

wait("initial secure connection", lambda s: s["isSecure"])
try:
    for cycle in range(2):
        radio(False)
        wait(f"cycle {cycle + 1}: phone radio off clears Mac session", lambda s: not s["isSecure"], seconds=40)
        radio(True)
        wait(f"cycle {cycle + 1}: saved identity authenticates after radio returns", lambda s: s["isSecure"])
finally:
    radio(True)
print("Physical Android Bluetooth recovery checks passed; saved pairing retained.", flush=True)
