#!/usr/bin/env python3
"""Fixed synthetic BLE staging test. No arbitrary file, external picker or user setting reset."""
import argparse
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("pid", type=int, help="Sapphire process explicitly launched with --phone-diagnostics")
parser.add_argument("--serial", required=True, help="Explicit authorized USB phone serial")
parser.add_argument("--adb", default="adb")
parser.add_argument("--sleep-after", action="store_true")
parser.add_argument("--sleep-during-transfer", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
directory = Path(tempfile.gettempdir()) / f"sapphire-phone-diagnostics-{args.pid}"
run = str(uuid.uuid4())

def adb(*command):
    return subprocess.run([args.adb, "-s", args.serial, *command], capture_output=True, text=True, check=True, timeout=30).stdout

def power():
    raw = adb("shell", "dumpsys", "power")
    mode = re.search(r"mWakefulness=(Awake|Asleep|Dozing|Dreaming)", raw)
    woke = re.search(r"mLastWakeTime=(\d+)", raw)
    if not mode or not woke:
        raise RuntimeError("Phone wakefulness cannot be verified")
    return mode.group(1), int(woke.group(1))

def sleep_phone():
    adb("shell", "input", "keyevent", "KEYCODE_SLEEP")
    for _ in range(20):
        observed = power()
        if observed[0] in {"Dozing", "Asleep"}:
            time.sleep(.3)
            if power() == observed:
                return observed
        time.sleep(.2)
    raise RuntimeError("Phone did not remain asleep during the final verification")

def state():
    return json.loads((directory / "state.json").read_text())

def command(action):
    subprocess.run(["python3", str(root / "scripts/phone-diagnostics.py"), "--pid", str(args.pid), action], check=True, stdout=subprocess.DEVNULL, timeout=10)

def fixture(action, transfer=None):
    command = ["shell", "am", "start", "-W", "-n", "dev.sapphire.companion/.FileTransferFixtureActivity", "--es", "fixture", action, "--es", "run", run]
    if transfer is not None:
        uuid.UUID(transfer)
        command += ["--es", "transfer", transfer]
    adb(*command)
    result = json.loads(adb("shell", "run-as", "dev.sapphire.companion", "cat", "files/file-transfer-fixture-state.json"))
    if result.get("run") != run:
        raise RuntimeError("Fixture report belongs to another run")
    return result.get("state")

def wait(label, predicate, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        current = state()
        if predicate(current):
            print("PASS:", label, flush=True)
            return current
        if current.get("fileFixtureReply") in {"fixture-error", "unavailable"}:
            raise RuntimeError("Fixture sender unavailable; no arbitrary file fallback")
        time.sleep(.2)
    # Never print the general diagnostic snapshot: it may contain normal status.
    raise RuntimeError("Timed out: " + label)

initial = state()
if not initial.get("isSecure") or not initial.get("fileTransferSupported") or initial.get("fileTransferBusy"):
    parser.error("An updated secure link with no active user transfer is required; pairing is never approved by this script.")
started = False
try:
    if fixture("begin") != "disabled":
        raise RuntimeError("Phone fixture is busy or refused setup; existing files/preferences left alone")
    started = True
    old = state().get("fileFixtureID")
    command("file-test-send")
    wait("phone rejects file offer while receiving is disabled", lambda s: s.get("fileFixtureID") != old and s.get("fileFixtureReply") == "disabled" and not s.get("fileFixtureBusy"))
    if fixture("enable") != "enabled":
        raise RuntimeError("Could not enable only the file-receive preference")
    old = state().get("fileFixtureID")
    sleeping = None
    if args.sleep_during_transfer:
        time.sleep(1)  # Let the setup Activity finish before the sleep observation.
        sleeping = sleep_phone()
        print("PASS: phone verified asleep before sending fixture bytes", flush=True)
    command("file-test-send")
    completed = wait("encrypted BLE transfer completes verified private staging", lambda s: bool(s.get("fileFixtureID")) and s.get("fileFixtureID") != old and s.get("fileFixtureReply") == "complete" and s.get("fileFixtureProgress") == 1 and not s.get("fileFixtureBusy"))
    if sleeping is not None:
        after = power()
        if after[0] not in {"Dozing", "Asleep"} or after[1] != sleeping[1]:
            raise RuntimeError("Phone woke during staging; background transfer claim rejected")
        print("PASS: phone asleep after staging with unchanged last-wake timestamp", flush=True)
    transfer = completed["fileFixtureID"]
    if fixture("expect", transfer) != "expected":
        raise RuntimeError("Could not bind phone verification to this exact transfer")
    if fixture("verify") != "verified":
        raise RuntimeError("Phone's independently read staged bytes/hash did not match the fixed fixture")
    print("PASS: phone independently verifies all 4,097 expected synthetic bytes and SHA-256", flush=True)
    if fixture("discard") != "discarded":
        raise RuntimeError("Phone did not discard the owned fixture")
    print("PASS: phone discards only the exact owned transfer", flush=True)
finally:
    try:
        if started:
            owned = state().get("fileFixtureID")
            if owned:
                fixture("expect", owned)
        command("file-test-remove")
    finally:
        try:
            restored = fixture("restore")
            if restored == "restored":
                print("PASS: original file-receive preference restored", flush=True)
            elif started or restored == "error":
                raise RuntimeError("Phone fixture preference restoration needs attention")
        finally:
            if args.sleep_after:
                mode, _ = sleep_phone()
                print("Phone verified:", mode, flush=True)
print("Live synthetic file-staging checks passed; no external picker, browser, message or user file used.", flush=True)
