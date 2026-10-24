#!/usr/bin/env python3
"""Fixed background clipboard relay. Mac uses a private pasteboard; phone original stays opaque. Never sleeps phone."""
import argparse,json,subprocess,tempfile,time,uuid,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('pid',type=int);p.add_argument('--serial',required=True);p.add_argument('--check-recovery',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[1];directory=Path(tempfile.gettempdir())/f'sapphire-phone-diagnostics-{a.pid}'
run=str(uuid.uuid4())
helper='dev.sapphire.companion.hotspothelper';app='dev.sapphire.companion'
def adb(*args):return subprocess.check_output(['adb','-s',a.serial,*args],text=True,stderr=subprocess.DEVNULL,timeout=25)
def state():return json.loads((directory/'state.json').read_text())
def command(action):subprocess.run(['python3',str(root/'scripts/phone-diagnostics.py'),'--pid',str(a.pid),action],check=True,stdout=subprocess.DEVNULL,timeout=10)
def wait(label,predicate,seconds=15):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  if predicate(state()):print('PASS:',label,flush=True);return
  time.sleep(.1)
 raise RuntimeError('Timed out: '+label)
def fixture(package,action,wanted,seconds=15):
 cls='dev.sapphire.helper.ClipboardFixtureActivity' if package==helper else '.ClipboardSyncFixtureActivity'
 report='clipboard-fixture.json' if package==helper else 'clipboard-sync-fixture.json'
 adb('shell','am','start','-W','-f','0x18000000','-n',package+'/'+cls,'--es','fixture',action,'--es','run',run)
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  try:s=json.loads(adb('shell','run-as',package,'cat','files/'+report))
  except (subprocess.CalledProcessError,json.JSONDecodeError):time.sleep(.1);continue
  if s.get('run')==run and (package!=helper or s.get('action')==action):
   value=s.get('state')
   if value in wanted:return value
   if value in {'blocked','error','unavailable','wrong-run','locked','still-focused'}:raise RuntimeError('Fixture '+action+': '+value)
  time.sleep(.1)
 raise RuntimeError('Timed out waiting for fixture '+action)
helper_attempted=app_attempted=False
try:
 command('clipboard-test-begin');wait('Mac private fixture pasteboard active',lambda s:s.get('clipboardFixtureActive'))
 if not state().get('isSecure'):raise RuntimeError('Resume the stored secure connection first; no pairing approval is attempted')
 helper_attempted=True
 assert fixture(helper,'prepare-relay',{'prepared'})=='prepared'
 app_attempted=True
 assert fixture(app,'begin',{'ready'})=='ready'
 assert fixture(helper,'copy-relay',{'copied-in-background'})=='copied-in-background'
 windows=adb('shell','dumpsys','window')
 focus=re.search(r'mCurrentFocus=([^\n]+)',windows)
 assert focus and app not in focus[1] and 'dev.sapphire.helper' not in focus[1], 'A Sapphire activity retained focus during the relay'
 print('PASS: neither Companion nor Helper has window focus during the copy',flush=True)
 wait('background helper → production Companion → encrypted BLE → marked private Mac pasteboard',lambda s:s.get('clipboardFixtureDelivered') and s.get('clipboardFixtureReceiveCount')==1)
 wait('real activity manager selects compact copied-link prompt',lambda s:s.get('clipboardFixturePromptVisible'),4)
 wait('copied-link prompt expires without browser opening',lambda s:not s.get('clipboardFixturePrompt'),7)
 for action in ['copy-sensitive','copy-remote']:
  assert fixture(helper,action,{'copied-in-background'})=='copied-in-background'
  time.sleep(2)
  assert state().get('clipboardFixtureReceiveCount')==1, action+' escaped filtering'
  assert not state().get('clipboardFixturePrompt'), action+' created prompt'
  print('PASS:',action,'does not relay or prompt',flush=True)
 if a.check_recovery:
  assert fixture(helper,'disable-relay',{'disabled'})=='disabled'
  deadline=time.monotonic()+5
  while fixture(app,'status',{'ready','needs_setup'})!='needs_setup':
   if time.monotonic()>=deadline:raise RuntimeError('Helper opt-out did not propagate')
   time.sleep(.2)
  assert fixture(helper,'enable-relay',{'enabled'})=='enabled'
  deadline=time.monotonic()+40
  while True:
   status=fixture(app,'status',{'ready','needs_setup','connecting'})
   if status=='ready':break
   if time.monotonic()>=deadline:raise RuntimeError('Automatic helper recovery did not finish')
   time.sleep(2)
  assert state().get('clipboardFixtureReceiveCount')==1, 'Recovery replayed existing clipboard'
  print('PASS: helper opt-out reports unavailable; automatic reauthorization recovery does not replay clipboard',flush=True)
 assert fixture(helper,'copy-relay',{'copied-in-background'})=='copied-in-background'
 wait('a later fresh copy of the same text relays again',lambda s:s.get('clipboardFixtureReceiveCount')==2)
finally:
 try:
  if app_attempted:fixture(app,'quiesce',{'quiesced'})
 finally:
  try:
   if helper_attempted:fixture(helper,'restore',{'restored'})
  finally:
   try:
    if app_attempted:fixture(app,'restore',{'restored'})
   finally:
    command('clipboard-test-end')
    wait('private Mac fixture removed; phone left awake as requested',lambda s:not s.get('clipboardFixtureActive'))
print('Live synthetic clipboard relay, filtering, prompt expiry and owned cleanup passed.',flush=True)
