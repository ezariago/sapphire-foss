#!/usr/bin/env python3
"""Native fixed-clipboard probe. Keeps original phone clip opaque/in-memory; restores only its own fixture."""
import argparse,json,subprocess,time,uuid,re
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--serial',required=True);a=p.parse_args()
run=str(uuid.uuid4())
def adb(*args):return subprocess.check_output(['adb','-s',a.serial,*args],text=True,stderr=subprocess.DEVNULL,timeout=25)
def start(action):adb('shell','am','start','-W','-n','dev.sapphire.companion.hotspothelper/dev.sapphire.helper.ClipboardFixtureActivity','--es','fixture',action,'--es','run',run)
def report(wanted,seconds=15):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  try:s=json.loads(adb('shell','run-as','dev.sapphire.companion.hotspothelper','cat','files/clipboard-fixture.json'))
  except (subprocess.CalledProcessError,json.JSONDecodeError):time.sleep(.2);continue
  if s.get('run')==run and s.get('state') in wanted:return s['state']
  time.sleep(.2)
 raise RuntimeError('Timed out waiting for fixed fixture report; no clipboard content printed')
state=None
try:
 adb('shell','input','keyevent','KEYCODE_WAKEUP');time.sleep(.5)
 start('begin')
 state=report({'verified-background','unavailable','blocked','still-focused','mismatch','disconnected','locked'})
 if state!='verified-background':raise RuntimeError('Background clipboard helper did not pass: '+state)
 print('PASS: fixed synthetic clip read through production helper with fixture app out of focus',flush=True)
finally:
 try:
  state_before_cleanup=state
  start('restore')
  state=report({'restored','wrong-run'})
  if state!='restored' and state_before_cleanup!='locked':raise RuntimeError('Fixture restoration was not confirmed; check whether the phone needs unlocking')
  print('PASS: locked setup touched no clipboard/preferences' if state_before_cleanup=='locked' else 'PASS: original helper preference restored; original clip restored only if own fixture still current',flush=True)
 finally:
  adb('shell','input','keyevent','KEYCODE_SLEEP')
  end=time.monotonic()+6
  while time.monotonic()<end:
   power=adb('shell','dumpsys','power')
   match=re.search(r'mWakefulness=(Asleep|Dozing)\b',power)
   if match:print('Phone verified:',match[1],flush=True);break
   time.sleep(.2)
  else:raise RuntimeError('Phone sleep could not be verified')
