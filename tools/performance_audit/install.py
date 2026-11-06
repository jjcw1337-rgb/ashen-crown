#!/usr/bin/env python3
"""Install this audit only; leave existing Claude nightly jobs and accounts untouched."""
import hashlib
from pathlib import Path
import plistlib
import subprocess
import os

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
LABEL = 'com.gamefactory.ashen-performance-audit'
DOMAIN = f'gui/{os.getuid()}'
RUNNER = Path('/Users/blaine/dev/ashen-crown-performance-audit-runner')
REPORTS = Path('/Users/blaine/Library/Application Support/ashen-performance-audit')
PLIST = Path('/Users/blaine/Library/LaunchAgents')/(LABEL+'.plist')

state = subprocess.run(['launchctl','print',DOMAIN+'/'+LABEL],capture_output=True,text=True)
if state.returncode == 0 and 'state = running' in state.stdout:
    raise SystemExit('Audit is running; install after it finishes. Nothing changed.')
files = ['audit.py','bootstrap.gd']
digest = hashlib.sha256(b''.join((HERE/name).read_bytes() for name in files)).hexdigest()[:16]
version = RUNNER/digest
version.mkdir(parents=True,exist_ok=True)
REPORTS.mkdir(parents=True,exist_ok=True)
for name in files:
    (version/name).write_bytes((HERE/name).read_bytes())
config = {
    'Label':LABEL,
    'ProgramArguments':['/usr/bin/python3','-I',str(version/'audit.py'),'--repo',str(REPO),'--scheduled'],
    'StartCalendarInterval':{'Hour':22,'Minute':30},
    'StartInterval':900,
    'EnvironmentVariables':{'PATH':'/Users/blaine/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'},
    'WorkingDirectory':str(REPO),
    'StandardOutPath':str(REPORTS/'launchd.log'),
    'StandardErrorPath':str(REPORTS/'launchd.log'),
    'ProcessType':'Background',
    'LowPriorityIO':True,
}
if PLIST.exists(): (RUNNER/'previous.plist').write_bytes(PLIST.read_bytes())
temp = PLIST.with_suffix('.tmp')
temp.write_bytes(plistlib.dumps(config)); temp.chmod(0o600)
subprocess.run(['plutil','-lint',str(temp)],check=True)
if state.returncode == 0: subprocess.run(['launchctl','bootout',DOMAIN+'/'+LABEL],check=True)
temp.replace(PLIST)
subprocess.run(['launchctl','bootstrap',DOMAIN,str(PLIST)],check=True)
print('Installed 22:30 nightly audit; busy retries every 15 minutes until 23:30, Mac local time.')
print('Reports:',REPORTS/'latest.md')
print('Runner:',version/'audit.py')
