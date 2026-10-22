#!/usr/bin/env python3
"""Exercise the real Mac link's sleep/wake handlers in --phone-diagnostics mode.

Usage: ./scripts/test-phone-lifecycle.py PID
Leaves connection scanning enabled; never approves pairing or changes Wi-Fi.
"""
import argparse
import json
import os
from pathlib import Path
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("pid", type=int)
args = parser.parse_args()
directory = Path(tempfile.gettempdir()) / f"sapphire-phone-diagnostics-{args.pid}"


def state():
    return json.loads((directory / "state.json").read_text())


def wait_for(predicate, description, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        current = state()
        if predicate(current):
            return current
        time.sleep(0.1)
    raise AssertionError(f"Timed out waiting for {description}")


def command(action):
    wait_for(lambda _: not (directory / "command.json").exists(), "previous command")
    temporary = directory / "lifecycle-test.tmp"
    temporary.write_text(json.dumps({"action": action}))
    temporary.chmod(0o600)
    os.replace(temporary, directory / "command.json")
    wait_for(lambda _: not (directory / "command.json").exists(), action)


def awake(s):
    return not s["isSleeping"] and s["bluetoothState"] >= 0 and not s["recoveryPending"]


def asleep(s):
    return (s["isSleeping"] and s["bluetoothState"] == -1
            and not s["isSecure"] and not s["isScanning"]
            and not s["isConnecting"] and not s["subscribed"]
            and s["queuedChunks"] == 0)


command("scan")
wait_for(awake, "initial Bluetooth manager")
for _ in range(3):
    command("simulate-sleep")
    wait_for(asleep, "complete transport teardown")
    command("simulate-wake")
    wait_for(awake, "fresh manager after wake")

# A deliberate disconnect while asleep must suppress wake reconnection.
command("simulate-sleep")
wait_for(asleep, "sleep before disconnect")
command("disconnect")
command("simulate-wake")
time.sleep(3)
assert not state()["reconnectAllowed"] and state()["bluetoothState"] == -1

# A second sleep during the wake delay cancels the pending recovery.
command("scan")
wait_for(awake, "restart after explicit disconnect")
command("simulate-sleep")
command("simulate-wake")
command("simulate-sleep")
time.sleep(3)
assert asleep(state()) and not state()["recoveryPending"]
command("simulate-wake")
wait_for(awake, "recovery after interrupted wake")

# A deliberate disconnect during the wake delay cancels the pending recovery.
command("simulate-sleep")
command("simulate-wake")
command("disconnect")
time.sleep(3)
assert not state()["reconnectAllowed"] and state()["bluetoothState"] == -1
command("scan")
wait_for(awake, "final reconnection scan")
print("Passed phone lifecycle checks: repeated wake, stale session cleanup, "
      "disconnect during sleep/recovery, and sleep during recovery.")
