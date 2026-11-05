#!/usr/bin/env python3
"""Staging cutover to a CI export, preserving old release/configuration for rollback.
Must run as root on the staging host. Never imports resources or reads credential values.
"""
import json,os,re,shutil,subprocess,sys,time
from pathlib import Path

def run(*args): return subprocess.check_output(args,text=True).strip()
def call(*args): subprocess.run(args,check=True)
root=Path('/opt/ashen-crown/staging');release=Path(sys.argv[1]).resolve()
assert release.parent==root/'releases' and (release/'AshenCrown.x86_64').is_file()
revision=(release/'DEPLOYED_REV').read_text().strip();assert re.fullmatch('[a-f0-9]{7}',revision)
# Refuse to kick anyone out. Join/leave counts come from this exact service process's journal.
for unit in ('ashen-crown-bg','ashen-crown-coop'):
 pid=run('systemctl','show',unit,'-p','MainPID','--value')
 if pid!='0':
  log=run('journalctl','_PID='+pid,'--no-pager','-o','cat')
  counts=re.findall(r'\((\d+) playing\)',log)
  if counts and int(counts[-1]):raise SystemExit(unit+': players present; wait for an empty world.')
  if 'server up' not in log:raise SystemExit(unit+': cannot verify startup/player log; inspect before cutover.')
manager='ashen-crown-lobbies'
if subprocess.run(['systemctl','is-active','--quiet',manager]).returncode==0:
 raise SystemExit('Lobby manager already active: drain matches and coordinate an update before reinstalling.')
container=run('docker','ps','-q','--filter','name=caddy');assert container and '\n' not in container
net=json.loads(run('docker','inspect','--format','{{json .NetworkSettings.Networks}}',container))
gateway=next(iter(net.values()))['Gateway'];assert re.fullmatch(r'172\.\d+\.\d+\.\d+',gateway)
backup=root/('lobby-rollback-'+str(int(time.time())));backup.mkdir(mode=0o700)
old=(root/'game').resolve();(backup/'previous-release').write_text(str(old)+'\n')
caddy=root/'backend/Caddyfile';shutil.copy2(caddy,backup/'Caddyfile')
for name in ('ashen-crown-coop.service','ashen-crown-bg.service'):
 shutil.copy2(Path('/etc/systemd/system')/name,backup/name)
config=caddy.read_text()
assert '\thandle {' in config and '\thandle /lobbies {' not in config
route='\thandle /lobbies {\n\t\trequest_body {\n\t\t\tmax_size 16KB\n\t\t}\n\t\treverse_proxy '+gateway+':7352\n\t}\n'
caddy.write_text(config.replace('\thandle {',route+'\thandle {',1))
# An earlier atomic install can leave Docker's bind mount on an old inode.
# Validate and reload an explicit copy; a later container restart remounts the persisted host file.
call('docker','cp',str(caddy),container+':/tmp/lobby-Caddyfile')
try:call('docker','exec',container,'caddy','validate','--config','/tmp/lobby-Caddyfile','--adapter','caddyfile')
except Exception:
 caddy.write_text((backup/'Caddyfile').read_text());raise
(root/'lobbies.env').write_text('LOBBY_PROXY_BIND='+gateway+'\n');(root/'lobbies.env').chmod(0o600)
shutil.copy2(release/'deploy/lobbies/ashen-crown-lobbies.service','/etc/systemd/system/ashen-crown-lobbies.service')
coop=(backup/'ashen-crown-coop.service').read_text()
coop=re.sub(r'^ExecStart=.*$', 'ExecStart=/bin/sh -c \'r=$$(readlink -f /opt/ashen-crown/staging/game); exec "$$r/AshenCrown.x86_64" --headless --path "$$r" -- --server --coop --port 24570\'',coop,flags=re.M)
Path('/etc/systemd/system/ashen-crown-coop.service').write_text(coop)
# Record rollback before changing active processes. Existing players were checked immediately above.
print('Rollback:',backup,flush=True)
call('systemctl','disable','--now','ashen-crown-bg')
call('systemctl','stop','ashen-crown-coop')
next_link=root/'game.lobby-next';next_link.symlink_to(release);os.replace(next_link,root/'game')
try:
 call('systemctl','daemon-reload')
 call('systemctl','start','ashen-crown-coop')
 call('systemctl','enable','--now',manager)
 call('docker','cp',str(caddy),container+':/tmp/lobby-Caddyfile')
 call('docker','exec',container,'caddy','reload','--config','/tmp/lobby-Caddyfile','--adapter','caddyfile')
 (root/'lobbies-enabled').write_text(revision+'\n')
except Exception:
 call('systemctl','stop',manager,'ashen-crown-coop')
 next_link.symlink_to(old);os.replace(next_link,root/'game')
 shutil.copy2(backup/'ashen-crown-coop.service','/etc/systemd/system/ashen-crown-coop.service')
 caddy.write_text((backup/'Caddyfile').read_text())
 call('systemctl','daemon-reload');call('systemctl','enable','--now','ashen-crown-bg');call('systemctl','start','ashen-crown-coop')
 call('docker','cp',str(caddy),container+':/tmp/lobby-Caddyfile')
 call('docker','exec',container,'caddy','reload','--config','/tmp/lobby-Caddyfile','--adapter','caddyfile')
 raise
print('Activated staging candidate',revision,'with one match slot; verify before publishing clients.')
