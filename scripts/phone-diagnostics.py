#!/usr/bin/env python3
"""Control the explicitly enabled local phone diagnostic mode (never approves pairing)."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("action", choices=["state", "pair", "scan", "connect", "disconnect", "quit", "qr", "hotspot", "hotspot-probe", "hotspot-leave", "clipboard-on", "clipboard-off", "simulate-sleep", "simulate-wake", "notification-test-action", "notification-test-reply", "notification-test-dismiss", "notification-test-mute", "notification-test-unmute", "media-test-play", "media-test-pause", "media-test-toggle", "media-test-next", "media-test-previous", "media-test-seek", "media-test-stop", "handoff-test-send", "file-test-send", "file-test-remove"])
parser.add_argument("id", nargs="?", help="Discovered peripheral UUID for connect")
parser.add_argument("--pid", type=int)
args = parser.parse_args()

pid = args.pid
if pid is None:
    executable = str(ROOT / "build/DerivedData/Build/Products/Release/Sapphire.app/Contents/MacOS/Sapphire")
    result = subprocess.run(["pgrep", "-f", executable], capture_output=True, text=True)
    pids = [int(p) for p in result.stdout.split()]
    if len(pids) != 1:
        parser.error("Pass --pid for the one local Sapphire process running with --phone-diagnostics.")
    pid = pids[0]
directory = Path(tempfile.gettempdir()) / f"sapphire-phone-diagnostics-{pid}"
state_file = directory / "state.json"
if not state_file.exists():
    parser.error(f"Diagnostic mode is not enabled for pid {pid}; launch the app with --phone-diagnostics.")

state = json.loads(state_file.read_text())
if args.action == "state":
    state["hasQR"] = bool(state.pop("qrPayload", ""))
    print(json.dumps(state, indent=2))
elif args.action == "qr":
    print(state.get("qrPayload", ""))  # Ephemeral public QR challenge only.
else:
    command = {"action": args.action}
    if args.action == "connect":
        if not args.id:
            parser.error("connect requires a discovered peripheral UUID")
        command["id"] = args.id
    temporary = directory / "command.tmp"
    temporary.write_text(json.dumps(command))
    temporary.chmod(0o600)
    os.replace(temporary, directory / "command.json")
    print(f"Queued {args.action} for local diagnostic process {pid}.")
