#!/usr/bin/env python3
"""Exercise live-test failure cleanup using fake ADB and a fixture diagnostic process."""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
UPPER = "ABCDEFAB-1234-4321-ABCD-123456789012"
FAKE_ADB = r'''#!/usr/bin/env python3
import json,os,pathlib,sys
root=pathlib.Path(os.environ['SAPPHIRE_FAKE_ADB_ROOT'])
args=sys.argv[1:]
assert args[:2]==['-s','fixture-only'], 'Real device access forbidden'
args=args[2:]
log=root/'calls.jsonl'
with log.open('a') as f:f.write(json.dumps(args)+'\n')
report=root/'report.json'
if args[:4]==['shell','am','start','-W']:
 def extra(name):
  i=args.index(name);return args[i+1]
 action=extra('fixture');run=extra('run')
 if action=='begin':state='blocked' if os.environ['SAPPHIRE_FAKE_SCENARIO']=='blocked' else 'disabled'
 elif action=='enable':state='enabled'
 elif action=='expect':
  assert extra('transfer')==os.environ['SAPPHIRE_FAKE_EXPECTED'], 'Transfer ID case changed during cleanup'
  state='expected'
 elif action=='verify':state='verified' if os.environ['SAPPHIRE_FAKE_SCENARIO'] in {'save-failure','success'} else 'mismatch'
 elif action=='save-refused':state='save-refused'
 elif action=='save':state='mismatch' if os.environ['SAPPHIRE_FAKE_SCENARIO']=='save-failure' else 'saved'
 elif action=='discard':state='discarded'
 elif action=='restore':state='wrong-run' if os.environ['SAPPHIRE_FAKE_SCENARIO']=='blocked' else ('error' if os.environ['SAPPHIRE_FAKE_SCENARIO']=='restore-failure' else 'restored')
 else:raise AssertionError(action)
 report.write_text(json.dumps({'run':run,'state':state,'action':action}));print('Complete')
 if action=='restore':(root/'restored').write_text(state)
 elif action=='expect':(root/'bound').write_text(extra('transfer'))
elif args[:3]==['shell','run-as','dev.sapphire.companion']:print(report.read_text())
elif args==['shell','input','keyevent','KEYCODE_SLEEP']:
 (root/'slept').write_text('yes');(root/'awake').unlink(missing_ok=True)
elif args==['shell','dumpsys','power']:
 mode='Awake' if (root/'awake').exists() else 'Dozing'
 woke=(root/'wake-time').read_text() if (root/'wake-time').exists() else '1'
 print('mWakefulness='+mode+'\nmStayOn=false\nmLastWakeTime='+woke)
else:raise AssertionError(args)
'''

def run_case(scenario):
    with tempfile.TemporaryDirectory(prefix="sapphire-live-harness-") as temporary:
        temp = Path(temporary)
        fake = temp / "fake-adb"
        fake.write_text(FAKE_ADB)
        fake.chmod(0o700)
        pid = 800000 + secrets.randbelow(100000)
        directory = Path(tempfile.gettempdir()) / f"sapphire-phone-diagnostics-{pid}"
        directory.mkdir(mode=0o700)
        snapshot = {"isSecure": True, "fileTransferSupported": True, "fileTransferBusy": False, "fileFixtureReply": "idle", "fileFixtureID": ""}
        (directory / "state.json").write_text(json.dumps(snapshot))
        environment = dict(os.environ, SAPPHIRE_FAKE_ADB_ROOT=str(temp), SAPPHIRE_FAKE_SCENARIO=scenario, SAPPHIRE_FAKE_EXPECTED=UPPER)
        command_line = ["python3", str(ROOT / "scripts/test-phone-file-transfer-live.py"), str(pid), "--serial", "fixture-only", "--adb", str(fake), "--sleep-after"]
        if scenario == "wake-during-transfer":command_line.append("--sleep-during-transfer")
        process = subprocess.Popen(command_line, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        sends = 0
        try:
            deadline = time.monotonic() + 15
            while process.poll() is None and time.monotonic() < deadline:
                command = directory / "command.json"
                if command.exists():
                    action = json.loads(command.read_text())["action"]
                    command.unlink()
                    if action == "file-test-send":
                        sends += 1
                        if sends == 2 and scenario == "wake-during-transfer":
                            (temp / "awake").write_text("yes"); (temp / "wake-time").write_text("2")
                        snapshot.update(fileFixtureID=UPPER if sends == 2 else "11111111-1234-4321-ABCD-123456789012", fileFixtureReply="disabled" if sends == 1 else "complete", fileFixtureProgress=0 if sends == 1 else 1, fileFixtureBusy=False)
                        target = directory / "state.tmp"
                        target.write_text(json.dumps(snapshot)); os.replace(target, directory / "state.json")
                    else:assert action == "file-test-remove"
                time.sleep(.005)
            output, error = process.communicate(timeout=2)
            assert (process.returncode == 0) == (scenario == "success"), (scenario, output, error)
            assert (temp / "slept").exists(), (scenario, error)
            assert "Phone verified: Dozing" in output, (scenario, output, error)
            if scenario == "wake-during-transfer":assert "Phone woke during staging" in error
            assert (temp / "restored").exists(), (scenario, error)
            if scenario != "blocked":assert (temp / "bound").read_text() == UPPER
            else:assert sends == 0
            print("PASS:", scenario, "attempts restoration and sleep without real ADB; exact transfer ID preserved")
        finally:
            if process.poll() is None:process.kill();process.wait()
            shutil.rmtree(directory)

for case in ["blocked", "verification-failure", "restore-failure", "wake-during-transfer", "save-failure", "success"]:run_case(case)
print("Live test harness failure cleanup passed with isolated fake transport only.")
