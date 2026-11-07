#!/usr/bin/env python3
"""On-demand game lobbies. Public HTTP is reverse-proxied through HTTPS; workers use loopback.
No shell commands are built from requests. Waiting lobbies allocate no game processes.
"""
import argparse, hashlib, json, os, secrets, sqlite3, subprocess, threading, time, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

MODES = {'arena': (2, 6), 'battlegrounds': (1, 16), 'sandbox': (1, 6)}
# The modes a new lobby may use (MpMode.MODES in the game).
LIVE_MODES = ('battlegrounds', 'arena', 'sandbox')
# What one match costs, measured on the staging droplet (4 GB, 2 vCPU) with bot players on the stripped server build
# (Blaine's capacity audit, 2026-11-05: a Battlegrounds world ~0.4-0.46 GB; 6 players fighting ~0.25 of a core, so the
# budget allows some heavier fights). (MB, cores). Arena is a small map with no monsters.
# Sandbox starts with a conservative provisional allowance; measure before increasing capacity.
COST = {'arena': (450, 0.15), 'battlegrounds': (480, 0.3), 'sandbox': (600, 0.3)}
# A match's longest life (s): a hung or forgotten world never holds a server forever. Arena is best of three short
# rounds; Battlegrounds runs as long as its players last.
LIMIT = {'arena': 45 * 60, 'battlegrounds': 3 * 3600, 'sandbox': 60 * 60}
FULL = 'Servers are full right now. Your lobby stays open: press Start again in a moment.'
class Rejected(Exception): pass
OUTDATED = 'Your game (build %s) is out of date: update it in the itch app, then try again.'
OTHER_BUILD = 'This match runs build %s and your game is build %s: everyone in a match needs the same build (update in the itch app).'
# Standing test lobbies (jj, 2026-11-07: "it just shows games created missing 1 player, i join it and the game
# starts"; "its just for me testing"): with --standing (staging), an admin's lobby list always has one of each of these
# on the admin's own build, every seat but one a bot. Joining fills it and the match starts at once; the match server
# plays the bot seats (game/systems/bots/MatchBots). Nobody but an admin sees or joins them.
# (mode, team size, capacity, name)
STANDING = [('battlegrounds', 1, 4, 'Test raid · solo'), ('battlegrounds', 2, 4, 'Test raid · duo'),
            ('arena', 1, 2, 'Test arena · 1v1'), ('arena', 2, 4, 'Test arena · 2v2'), ('arena', 3, 6, 'Test arena · 3v3')]
BOT_CLASSES = ['knight', 'archer', 'warlock', 'wraith', 'demon']
BOT_NAMES = ['Kael', 'Brannoc', 'Ysolde', 'Mirelle', 'Corvin', 'Thessaly', 'Orrin', 'Vesna', 'Hadrik', 'Liora', 'Garrow', 'Ilsa', 'Torvald', 'Selka', 'Rook']
STANDING_IDLE = 6 * 3600     # an unused standing lobby (an old build's) closes after this long
ADMIN_ONLY = 'Test lobbies are for admins.'

class Lobbies:
    def __init__(self, path, launch, stop, slots=1, clock=time.time):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute('CREATE TABLE IF NOT EXISTS state (id TEXT PRIMARY KEY, data TEXT NOT NULL)')
        self.db.execute('CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY, user TEXT NOT NULL, data TEXT NOT NULL)')
        self.receipts={key:dict(user=uid,**json.loads(data)) for key,uid,data in self.db.execute('SELECT id,user,data FROM receipts')}
        self.lock = threading.RLock(); self.launch = launch; self.stop = stop
        self.slots = slots; self.clock = clock; self.rooms = {}
        self.standing = False    # (--standing: staging's test lobbies, STANDING)
        # Which game builds have a match server here (Service: the deployed server builds); tests leave it open.
        self.has_build = lambda rev: True
        for key, data in self.db.execute('SELECT id,data FROM state'):
            room = json.loads(data)
            # A controller restart never silently resumes an uncertain match.
            if room['state'] in ('starting', 'playing'):
                room['state'] = 'aborted'; room['reason'] = 'Server restarted; match cancelled.'
                self.settle(room,-1)
            self.rooms[key] = room
        self.persist()
    def persist(self):
        with self.db:
            for key, room in self.rooms.items():
                self.db.execute('INSERT OR REPLACE INTO state VALUES (?,?)', (key, json.dumps(room)))
            for key, receipt in self.receipts.items():
                self.db.execute('INSERT OR REPLACE INTO receipts VALUES (?,?,?)',(key,receipt['user'],json.dumps({k:v for k,v in receipt.items() if k!='user'})))
    def receipt(self,r,uid,items):
        key=r['id']+':'+uid
        self.receipts.setdefault(key,dict(user=uid,id=key,character=r['members'][uid]['character'],items=items,acked=False))
    def settle(self,r,winner=-1):
        if r.get('settled',False): return
        winners=[u for u,m in r['members'].items() if m['team']==winner]
        rewards={u:[] for u in r['members']}
        lost=[]
        for uid,m in r['members'].items():
            item=m.get('stake')
            if not item:continue
            if winner<0 or not winners or uid in winners: rewards[uid].append(item)
            else: lost.append(item)
        for i,item in enumerate(lost): rewards[winners[i%len(winners)]].append(item)
        for uid,m in r['members'].items():
            if m.get('stake') or rewards[uid]: self.receipt(r,uid,rewards[uid])
        r['settled']=True
    def room(self, rid):
        if rid not in self.rooms: raise Rejected('That lobby is no longer available.')
        return self.rooms[rid]
    def public(self, r, uid):
        out = {k:r[k] for k in ('id','name','mode','team_size','capacity','state','owner','members','created','reason','wager')}
        out = json.loads(json.dumps(out))
        out['joined']=sum(not m.get('departed',False) for m in r['members'].values())
        out['joinable'] = r['state']=='waiting' or (r['state']=='playing' and r.get('joinable',False))
        # (jj, 2026-11-07) a match you left (extracted, fell or quit) can't take you back: it isn't offered to you
        if uid in r['members'] and r['members'][uid].get('departed',False):
            out['joinable'] = False; out['left'] = True
        for m in out['members'].values(): m.pop('ticket', None)
        if uid in r['members'] and not r['members'][uid].get('departed',False) and r['state'] in ('starting','playing'):
            out['address'] = r.get('address','') if r.get('listening',False) else ''; out['ticket'] = r['members'][uid].get('ticket','')
        return out
    def call(self, uid, op, p, admin=False):
        with self.lock:
            self.sweep()
            if op == 'list' and admin and self.standing: self.ensure_standing(str(p.get('version','dev')))
            if op=='receipts': return {'receipts':[v for v in self.receipts.values() if v['user']==uid and not v['acked']]}
            if op=='ack':
                receipt=self.receipts.get(str(p.get('receipt','')),{})
                if receipt.get('user')!=uid: raise Rejected('Unknown reward receipt.')
                receipt['acked']=True;self.persist();return {'ok':True}
            if op == 'list': return {'lobbies':[self.public(r,uid) for r in self.rooms.values() if r['state'] in ('waiting','starting','playing') and not (uid in r['members'] and r['members'][uid].get('departed',False)) and (admin or not r.get('standing'))], 'slots':self.slots}
            if op == 'create':
                mode = p.get('mode'); team = p.get('team_size',1)
                if mode not in LIVE_MODES or type(team) is not int or team not in (1,2,3): raise Rejected('Choose a supported mode and team size.')
                if mode=='battlegrounds' and team not in (1,2): raise Rejected('Battlegrounds is solo or duo.')
                if mode=='sandbox': team=1
                if any(uid in r['members'] and not r['members'][uid].get('departed',False) and r['state'] in ('waiting','starting','playing') for r in self.rooms.values()): raise Rejected('Leave your current lobby first.')
                if p.get('wager',False) and mode!='arena': raise Rejected('Optional stakes are for Arena; Battlegrounds already has its extraction rules.')
                # (2026-11-07: a client on another build froze on "Joining…" at a match server whose network calls
                # differ) a lobby runs the server build of the game that made it; a build with no server here is out
                # of date. "dev" (a local build) is never gated.
                rev = str(p.get('version','dev'))
                if rev != 'dev' and not self.has_build(rev): raise Rejected(OUTDATED % rev)
                rid = secrets.token_hex(8)
                r = dict(id=rid,name=str(p.get('name','Adventure'))[:48],mode=mode,team_size=team,capacity=team*2 if mode=='arena' else MODES[mode][1],state='waiting',owner=uid,members={},created=self.clock(),touched=self.clock(),reason='',wager=bool(p.get('wager',False)),version=rev)
                self.rooms[rid]=r; self.add(r,uid,p)
            else:
                r=self.room(str(p.get('id','')))
                if op == 'join':
                    if r.get('standing') and not admin: raise Rejected(ADMIN_ONLY)
                    self.add(r,uid,p)
                    # a standing lobby is one seat short: the person who fills it starts it
                    if r.get('standing') and sum(not m.get('departed',False) for m in r['members'].values())>=r['capacity']:
                        for m in r['members'].values(): m['ready']=True
                        self.begin(r)
                elif op == 'get':
                    if uid in r['members']: r['members'][uid]['seen']=self.clock()
                elif op == 'leave':
                    if uid not in r['members']: raise Rejected('You are not in that lobby.')
                    if r['state']!='waiting': raise Rejected('Leave through the match exit after it starts.')
                    if r['members'][uid].get('stake'): self.receipt(r,uid,[r['members'][uid]['stake']])
                    del r['members'][uid]
                    for m in r['members'].values(): m['ready']=False
                    if not r['members']: r['state']='closed'
                    elif uid==r['owner']: r['owner']=next(iter(r['members']))
                elif op=='stake':
                    if r['state']!='waiting' or uid not in r['members'] or not r['wager']: raise Rejected('This lobby is not accepting stakes.')
                    m=r['members'][uid];item=p.get('item',{})
                    if not isinstance(item,dict) or not isinstance(item.get('base'),str) or not isinstance(item.get('uid'),str) or len(item['uid'])<12 or item['base']=='gold': raise Rejected('Select a valid item.')
                    if m.get('stake') and m['stake']!=item: raise Rejected('A stake is already locked for this entry.')
                    if not m.get('stake'):
                        for other in self.rooms.values():
                            if other['state'] in ('waiting','starting','playing') and any(x.get('stake',{}).get('uid')==item['uid'] for x in other['members'].values()): raise Rejected('That item is already committed.')
                    if not m.get('stake'):
                        m['stake']=item
                        for x in r['members'].values():x['ready']=False
                    m['seen']=self.clock()
                elif op in ('ready','team'):
                    if r['state']!='waiting' or uid not in r['members']: raise Rejected('This lobby is not waiting for players.')
                    if op=='team':
                        team=p.get('team')
                        if type(team) is not int or team not in range(self.teams(r)) or self.teams(r)<2: raise Rejected('Choose a team.')
                        if sum(m['team']==team for u,m in r['members'].items() if u!=uid)>=r['team_size']: raise Rejected('That team is full.')
                        r['members'][uid]['team']=team
                        for m in r['members'].values(): m['ready']=False
                    else:
                        if p.get('ready',False) and r['wager'] and not r['members'][uid].get('stake'): raise Rejected('Lock one item first, then confirm Ready to accept the displayed stakes.')
                        r['members'][uid]['ready']=bool(p.get('ready',False))
                    r['members'][uid]['seen']=self.clock()
                elif op=='pick':
                    # a member's class (Battlegrounds: run_<class>) or survivor (Arena) changes while the lobby waits;
                    # it un-readies them, so nobody starts on a choice the others haven't seen
                    if r['state']!='waiting' or uid not in r['members']: raise Rejected('This lobby is not waiting for players.')
                    char=str(p.get('character',''))
                    if not char or len(char)>100 or not all(c.isalnum() or c in '-_' for c in char): raise Rejected('Select a character first.')
                    if r['members'][uid].get('stake'): raise Rejected('Your item is locked for this lobby.')
                    r['members'][uid]['character']=char
                    r['members'][uid]['name']=str(p.get('player',r['members'][uid]['name']))[:32]
                    r['members'][uid]['ready']=False
                    r['members'][uid]['seen']=self.clock()
                elif op=='start':
                    if uid!=r['owner'] or r['state']!='waiting': raise Rejected('Only the waiting lobby owner can start.')
                    if r['wager'] and not all(m.get('stake') for m in r['members'].values()): raise Rejected('Everyone must commit an item.')
                    if not all(m['ready'] for m in r['members'].values()): raise Rejected('Everyone must be ready.')
                    if r['mode']=='arena' and any(sum(m['team']==t for m in r['members'].values())!=r['team_size'] for t in (0,1)): raise Rejected('Fill both teams before starting.')
                    self.begin(r)
                else: raise Rejected('Unknown lobby action.')
                if r['state']=='waiting': r['touched']=self.clock()
            self.persist(); return {'lobby':self.public(r,uid)}
    def begin(self,r):
        # the match server starts: tickets for the people, the room's manifest to a fresh process (Service.launch)
        busy=sum(x['state'] in ('starting','playing') for x in self.rooms.values())
        if busy>=self.slots: raise Rejected(FULL)
        r['state']='starting'; r['started']=self.clock(); r['worker_key']=secrets.token_hex(32)
        for m in r['members'].values(): m['ticket']=secrets.token_hex(32); m['redeemed']=False; m['issued']=self.clock()
        try: r['address']=self.launch(r)
        except Exception as exc:
            r['state']='waiting'; r['reason']=str(exc) if isinstance(exc,Rejected) else 'The match could not start. Try again.'
            self.persist(); raise Rejected(r['reason'])
    def ensure_standing(self,rev):
        # one waiting standing lobby of each kind on this build; a joined one is replaced by a fresh one
        for mode,team,cap,name in STANDING:
            key='%s:%d' % (mode,team)
            mine=[r for r in self.rooms.values() if r.get('standing')==key and r.get('version')==rev and r['state']=='waiting']
            if mine:
                for r in mine: r['touched']=self.clock()
                continue
            if rev!='dev' and not self.has_build(rev): continue
            rid=secrets.token_hex(8)
            r=dict(id=rid,name=name,mode=mode,team_size=team,capacity=cap,state='waiting',owner='',members={},created=self.clock(),touched=self.clock(),reason='',wager=False,version=rev,standing=key)
            for i in range(cap-1):
                n=len(self.rooms)*7+i
                cls=BOT_CLASSES[(i+len(self.rooms))%len(BOT_CLASSES)]
                r['members']['bot:%s:%d'%(rid,i)]={'name':'Bot %s'%BOT_NAMES[n%len(BOT_NAMES)],'character':'run_'+cls,'team':self.open_team(r),'ready':True,'seen':self.clock(),'bot':True}
            r['owner']=next(iter(r['members']))
            self.rooms[rid]=r
        self.persist()
    def teams(self,r):
        # Arena: two teams of team_size. Battlegrounds duo: pairs (capacity / 2 of them). Solo: everyone alone.
        if r['mode']=='arena': return 2
        if r['mode']=='battlegrounds' and r['team_size']==2: return r['capacity']//2
        return 1
    def open_team(self,r):
        # the first team with room (a Battlegrounds solo lobby's players are each their own: team = join order)
        n=self.teams(r)
        if n==1 and r['mode']=='battlegrounds': return len(r['members'])
        for t in range(n):
            if sum(m['team']==t and not m.get('departed',False) for m in r['members'].values())<r['team_size']: return t
        return 0
    def add(self,r,uid,p):
        if r['state']!='waiting' and not (r['state']=='playing' and r.get('joinable',False)): raise Rejected('This match has started. Join a waiting lobby or create another.')
        if uid in r['members']:
            if r['members'][uid].get('departed',False): raise Rejected('You already left this match. Join or create a different lobby.')
            return
        if r['id']+':'+uid in self.receipts: raise Rejected('This lobby entry has already refunded your stake. Create or join a new lobby.')
        if any(uid in x['members'] and not x['members'][uid].get('departed',False) and x['state'] in ('starting','playing','waiting') and x['id']!=r['id'] for x in self.rooms.values()): raise Rejected('Leave your current lobby first.')
        if sum(not m.get('departed',False) for m in r['members'].values())>=r['capacity']: raise Rejected('Lobby full.')
        char=str(p.get('character',''))
        if not char or len(char)>100 or not all(c.isalnum() or c in '-_' for c in char): raise Rejected('Select a character first.')
        mine=str(p.get('version','dev')); theirs=str(r.get('version','dev'))
        if mine!='dev' and theirs!='dev' and mine!=theirs: raise Rejected(OTHER_BUILD % (theirs, mine))
        team=self.open_team(r)
        r['members'][uid]={'name':str(p.get('player','Adventurer'))[:32],'character':char,'team':team,'ready':False,'seen':self.clock()}
        for m in r['members'].values(): m['ready']=False
        if r['state']=='playing':
            r['members'][uid].update(ticket=secrets.token_hex(32),redeemed=False,issued=self.clock())
    def worker(self,rid,key,op,p):
        with self.lock:
            r=self.room(rid)
            if not secrets.compare_digest(str(r.get('worker_key','')),key) or not key: raise Rejected('Invalid worker.')
            if op=='depart':
                member=r['members'].get(str(p.get('user','')))
                if member: member['departed']=True
                self.persist();return {'ok':True}
            if op=='listening':
                r['listening']=True;self.persist();return {'ok':True}
            if op=='redeem':
                if r['state'] not in ('starting','playing'): raise Rejected('Admission expired.')
                for uid,m in r['members'].items():
                    if secrets.compare_digest(str(m.get('ticket','')),str(p.get('ticket',''))) and not m.get('redeemed',False) and self.clock()-m.get('issued',0)<180:
                        m['redeemed']=True;self.persist();return {'user':uid,'team':m['team'],'character':m['character'],'name':m['name']}
                raise Rejected('Invalid or already used ticket.')
            if op=='state':
                state=p.get('state')
                if state not in ('playing','finished','aborted'): raise Rejected('Invalid match state.')
                if r['state'] not in ('starting','playing'): return {'ok':True}
                r['joinable']=bool(p.get('joinable',False)) and r['mode']!='arena' and state=='playing'
                r['state']=state;r['reason']=str(p.get('reason',''))[:200];r['touched']=self.clock()
                if state in ('finished','aborted'): self.settle(r,int(p.get('winner',-1)) if state=='finished' else -1)
                self.persist();return {'ok':True}
            raise Rejected('Unknown worker action.')
    def sweep(self):
        now=self.clock()
        for r in self.rooms.values():
            if r['state']=='waiting':
                if r.get('standing') and all(m.get('bot') for m in r['members'].values()) and now-r.get('touched',now)>STANDING_IDLE:
                    r['state']='closed'; continue
                for uid in list(r['members']):
                    if r['members'][uid].get('bot'): continue
                    if now-r['members'][uid]['seen']>90:
                        if r['members'][uid].get('stake'): self.receipt(r,uid,[r['members'][uid]['stake']])
                        del r['members'][uid]
                if not r['members']: r['state']='closed'
                elif r['owner'] not in r['members']: r['owner']=next(iter(r['members']))
            elif r['state']=='playing' and now-r.get('touched',now)>60:
                r['state']='aborted';r['reason']='Match server stopped responding.';self.settle(r,-1);self.stop(r['id'])
            elif r['state'] in ('starting','playing') and now-r.get('started',now)>(180 if r['state']=='starting' else LIMIT.get(r['mode'],7200)):
                r['state']='aborted';r['reason']='Match timed out.';self.settle(r,-1);self.stop(r['id'])
            elif r['state'] in ('finished','aborted') and not r.get('retired',False) and now-r.get('touched',now)>30:
                # A finished match's process quits by itself; this only stops one that hung on its way out.
                r['retired']=True;self.stop(r['id'])

class Service:
    def __init__(self,args):
        self.args=args;args.game=str(Path(args.game).resolve());self.processes={};self.root=Path(args.state);self.root.mkdir(parents=True,exist_ok=True)
        revision=Path(args.game)/"DEPLOYED_REV"
        self.version=revision.read_text().strip() if revision.exists() else "dev"
        if not args.dev and self.version=="dev": raise RuntimeError("Deploy an imported release with DEPLOYED_REV before starting the public lobby service.")
        self.model=Lobbies(str(self.root/'lobbies.sqlite'),self.launch,self.stop,args.slots)
        self.model.standing=bool(args.standing);self._admins={}
        self.model.has_build=lambda rev: self.binary_for(rev) is not None
    def binary_for(self,rev):
        # the server builds sit side by side (update.sh keeps the newest three: <server>/<rev>/AshenCrown.x86_64)
        if not self.args.server_binary: return None
        b=Path(self.args.server_binary).resolve().parent.parent/str(rev)/'AshenCrown.x86_64'
        return str(b) if b.is_file() else None
    def launch(self,r):
        # Room for one more? Free memory for this mode's world plus headroom, and a CPU budget across the running
        # matches (their measured cost, COST): no fixed slot count, so a bigger machine simply holds more.
        mb,cpu=COST.get(r['mode'],(500,0.3))
        free=self.mem_available_mb()
        if free is not None and free<mb+self.args.min_free_mb: raise Rejected(FULL)
        alive={rid:p for rid,p in self.processes.items() if p[0].poll() is None}
        used=sum(COST.get(p[2],(0,0.3))[1] for p in alive.values())
        if used+cpu>self.cpus()*self.args.cpu_budget-self.args.reserve_cpu: raise Rejected(FULL)
        ports={p[1] for p in alive.values()}
        port=next((p for p in range(self.args.first_port,self.args.first_port+self.args.ports) if p not in ports),None)
        if port is None: raise Rejected(FULL)
        manifest={k:r[k] for k in ('id','mode','team_size','capacity','worker_key','members')}
        manifest['broker']='http://127.0.0.1:%d'%self.args.port
        path=self.root/(r['id']+'.json');path.write_text(json.dumps(manifest));path.chmod(0o600)
        log=(self.root/(r['id']+'.log')).open('ab')
        args=['--','--server','--port',str(port),'--match-config',str(path)]
        # the stripped dedicated-server export (one file, its pack inside) when deployed; else the game itself
        binary=self.binary_for(r.get('version','dev')) or self.args.server_binary
        lean=binary and os.path.isfile(binary)
        cmd=[binary,'--headless']+args if lean else [self.args.godot,'--headless','--path',self.args.game]+args
        proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
        log.close();self.processes[r['id']]=(proc,port,r['mode'])
        return '%s:%d'%(self.args.public_host,port)
    def mem_available_mb(self):
        p=Path('/proc/meminfo')
        if not p.exists(): return None
        info=dict((line.split(':')[0],int(line.split()[1])) for line in p.read_text().splitlines())
        return info.get('MemAvailable',0)//1024
    def cpus(self): return os.cpu_count() or 1
    def stop(self,rid):
        pair=self.processes.get(rid)
        if pair and pair[0].poll() is None:
            proc=pair[0];proc.terminate()
            def force():
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired: proc.kill()
            threading.Thread(target=force,daemon=True).start()
    def admin(self,header):
        # (the Nakama module's admin_status, as the game asks it with the player's own session; cached a minute)
        if self.args.dev: return header.startswith('Bearer dev-admin')
        now=time.time();key=hashlib.sha256(header.encode()).hexdigest()
        hit=self._admins.get(key)
        if hit and now-hit[1]<60: return hit[0]
        req=urllib.request.Request(self.args.nakama.rstrip('/')+'/v2/rpc/admin_status?unwrap',data=b'{}',headers={'Authorization':header,'Content-Type':'application/json'},method='POST')
        try:
            with urllib.request.urlopen(req,timeout=5) as response: ok=bool(json.load(response).get('admin',False))
        except Exception: ok=False
        self._admins[key]=(ok,now)
        return ok
    def user(self,header):
        if self.args.dev:
            if not header.startswith('Bearer dev-') or len(header)>100: raise Rejected('Local test identity required.')
            return hashlib.sha256(header.encode()).hexdigest()[:24]
        if not header.startswith('Bearer '): raise Rejected('Sign in first.')
        req=urllib.request.Request(self.args.nakama.rstrip('/')+'/v2/account',headers={'Authorization':header})
        try:
            with urllib.request.urlopen(req,timeout=5) as response: return json.load(response)['user']['id']
        except Exception: raise Rejected('Your session expired. Sign in again.')
    def reap(self):
        with self.model.lock:
            for rid,(proc,*_) in list(self.processes.items()):
                if proc.poll() is not None:
                    r=self.model.rooms[rid]
                    if r['state'] in ('starting','playing'): r['state']='aborted';r['reason']='The match server stopped.';self.model.settle(r,-1)
                    del self.processes[rid]
            self.model.sweep();self.model.persist()

class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass # Never log sessions or admission tokens.
    def do_POST(self):
        status=200
        try:
            length=int(self.headers.get('Content-Length','0'))
            if length<0 or length>16384: raise Rejected('Request too large.')
            p=json.loads(self.rfile.read(length));svc=self.server.service
            if not isinstance(p,dict): raise Rejected('Invalid request.')
            if self.path=='/worker':
                if self.client_address[0] not in ('127.0.0.1','::1'): raise Rejected('Local workers only.')
                result=svc.model.worker(str(p.get('id','')),self.headers.get('X-Worker-Key',''),str(p.get('op','')),p)
            elif self.path=='/lobbies':
                # A lobby keeps its creator's build (version) and runs that build's match server; a game on another
                # build can't join it, and one whose build has no server here is told to update (Lobbies.call).
                header=self.headers.get('Authorization','');op=str(p.get('op',''))
                uid=svc.user(header)
                result=svc.model.call(uid,op,p,admin=op in ('list','join') and svc.admin(header))
            else: raise Rejected('Unknown endpoint.')
        except (Rejected,ValueError,KeyError,TypeError) as e: status=400;result={'error':str(e)}
        except Exception: status=500;result={'error':'Lobby service unavailable.'}
        data=json.dumps(result).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--state',default='/var/lib/ashen-lobbies');ap.add_argument('--game',required=True);ap.add_argument('--godot',default='godot');ap.add_argument('--bind',default='127.0.0.1');ap.add_argument('--proxy-bind',default='');ap.add_argument('--port',type=int,default=7352);ap.add_argument('--public-host',default='127.0.0.1');ap.add_argument('--first-port',type=int,default=24600);ap.add_argument('--ports',type=int,default=16);ap.add_argument('--slots',type=int,default=32);ap.add_argument('--min-free-mb',type=int,default=300);ap.add_argument('--cpu-budget',type=float,default=0.9);ap.add_argument('--reserve-cpu',type=float,default=0.3);ap.add_argument('--server-binary',default='');ap.add_argument('--nakama',default='http://127.0.0.1:7350');ap.add_argument('--dev',action='store_true');ap.add_argument('--standing',action='store_true',help="staging: admins' standing test lobbies (STANDING)");args=ap.parse_args()
    if args.dev and (args.bind!='127.0.0.1' or args.proxy_bind): ap.error('Development identities are loopback-only.')
    svc=Service(args);server=ThreadingHTTPServer((args.bind,args.port),Handler);server.service=svc
    if args.proxy_bind:
        # A private Docker bridge listener for Caddy; worker calls still require loopback.
        proxy=ThreadingHTTPServer((args.proxy_bind,args.port),Handler);proxy.service=svc
        threading.Thread(target=proxy.serve_forever,daemon=True).start()
    def tick():
        while True: time.sleep(2);svc.reap()
    threading.Thread(target=tick,daemon=True).start()
    try: server.serve_forever()
    finally:
        for rid in list(svc.processes): svc.stop(rid)
if __name__=='__main__': main()
