import tempfile, unittest
from pathlib import Path
from service import Lobbies, Rejected

class LobbyTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.now=1000;self.started=[];self.stopped=[]
  self.m=Lobbies(str(Path(self.temp.name)/'state.sqlite'),self.launch,self.stopped.append,1,lambda:self.now)
 def tearDown(self):self.m.db.close();self.temp.cleanup()
 def launch(self,r):self.started.append(r['id']);return '127.0.0.1:24600'
 def create(self,uid='a',mode='arena',size=1):return self.m.call(uid,'create',{'mode':mode,'team_size':size,'character':'hero','player':uid})['lobby']
 def act(self,uid,r,op,**kw):return self.m.call(uid,op,dict(id=r['id'],character='hero',**kw))
 def pair(self,size=1):
  r=self.create(size=size)
  for i in range(1,2*size):self.act(str(i),r,'join')
  for uid in self.m.rooms[r['id']]['members']:self.act(uid,r,'ready',ready=True)
  return r
 def test_waiting_is_lightweight(self):self.create();self.assertEqual(self.started,[])
 def test_terminal_worker_gets_bounded_shutdown_grace(self):
  r=self.pair();self.act('a',r,'start');live=self.m.rooms[r['id']]
  self.m.worker(r['id'],live['worker_key'],'state',{'state':'finished','winner':0})
  self.now+=20;self.m.sweep();self.assertEqual(self.stopped,[])
  self.now+=11;self.m.sweep();self.assertEqual(self.stopped,[r['id']])
  self.m.sweep();self.assertEqual(self.stopped,[r['id']])
 def test_owner_start_only(self):
  r=self.pair()
  with self.assertRaises(Rejected):self.act('1',r,'start')
 def test_ready_required(self):
  r=self.create();self.act('1',r,'join')
  with self.assertRaises(Rejected):self.act('a',r,'start')
 def test_balanced_teams_required(self):
  r=self.create(size=2);self.act('a',r,'ready',ready=True)
  with self.assertRaises(Rejected):self.act('a',r,'start')
 def test_teams_1_2_3(self):
  for size in (1,2,3):
   r=self.pair(size);self.act('a',r,'start');self.assertEqual(len(self.started),size)
   self.m.rooms[r['id']]['state']='finished'
 def test_full(self):
  r=self.pair()
  with self.assertRaises(Rejected):self.act('extra',r,'join')
 def test_cross_lobby_membership(self):
  self.create()
  with self.assertRaises(Rejected):self.create()
 def test_team_change_resets_ready(self):
  r=self.create(size=2);self.act('a',r,'ready',ready=True);self.act('a',r,'team',team=1)
  self.assertFalse(self.m.rooms[r['id']]['members']['a']['ready'])
 def test_new_join_resets_ready(self):
  r=self.create();self.act('a',r,'ready',ready=True);self.act('1',r,'join')
  self.assertFalse(self.m.rooms[r['id']]['members']['a']['ready'])
 def test_host_migrates(self):
  r=self.pair();self.act('a',r,'leave');self.assertEqual(self.m.rooms[r['id']]['owner'],'1')
 def test_empty_closes(self):
  r=self.create();self.act('a',r,'leave');self.assertEqual(self.m.rooms[r['id']]['state'],'closed')
 def test_waves_and_bg_can_start_solo(self):
  for mode in ('waves','battlegrounds'):
   r=self.create(mode=mode);self.act('a',r,'ready',ready=True);self.act('a',r,'start');self.assertEqual(self.m.rooms[r['id']]['state'],'starting');self.m.rooms[r['id']]['state']='finished'
 def test_capacity_limit(self):
  r=self.pair();self.act('a',r,'start');second=self.create('x','waves');self.act('x',second,'ready',ready=True)
  with self.assertRaises(Rejected):self.act('x',second,'start')
  self.assertEqual(self.m.rooms[second['id']]['state'],'waiting')
 def test_worker_admission_single_use(self):
  r=self.pair();self.act('a',r,'start');r=self.m.rooms[r['id']];token=r['members']['a']['ticket']
  got=self.m.worker(r['id'],r['worker_key'],'redeem',{'ticket':token});self.assertEqual(got['user'],'a')
  with self.assertRaises(Rejected):self.m.worker(r['id'],r['worker_key'],'redeem',{'ticket':token})
 def test_wrong_worker_rejected(self):
  r=self.pair();self.act('a',r,'start')
  with self.assertRaises(Rejected):self.m.worker(r['id'],'wrong','state',{'state':'finished'})
 def test_no_ticket_leak(self):
  r=self.pair();self.act('a',r,'start');listing=self.m.call('stranger','list',{})['lobbies'][0]
  self.assertNotIn('ticket',listing);self.assertNotIn('ticket',listing['members']['a']);self.assertNotIn('worker_key',listing)
 def test_address_waits_for_listening(self):
  r=self.pair();result=self.act('a',r,'start')['lobby'];self.assertEqual(result['address'],'')
  rr=self.m.rooms[r['id']];self.m.worker(r['id'],rr['worker_key'],'listening',{})
  self.assertTrue(self.act('a',r,'get')['lobby']['address'])
 def test_startup_timeout_stops_worker(self):
  r=self.pair();self.act('a',r,'start');self.now+=181;self.m.sweep();self.assertEqual(self.stopped,[r['id']])
 def test_stale_waiting_members_expire(self):
  r=self.create();self.now+=91;self.m.sweep();self.assertEqual(self.m.rooms[r['id']]['state'],'closed')
 def test_launch_failure_preserves_lobby(self):
  r=self.pair();self.m.launch=lambda r:(_ for _ in ()).throw(OSError())
  with self.assertRaises(Rejected):self.act('a',r,'start')
  self.assertEqual(self.m.rooms[r['id']]['state'],'waiting')
 def test_restart_aborts_uncertain_match(self):
  r=self.pair();self.act('a',r,'start')
  other=Lobbies(str(Path(self.temp.name)/'state.sqlite'),self.launch,self.stopped.append)
  self.assertEqual(other.rooms[r['id']]['state'],'aborted');other.db.close()
 def test_join_started_rejected(self):
  r=self.create(mode='waves');self.act('a',r,'ready',ready=True);self.act('a',r,'start')
  with self.assertRaises(Rejected):self.act('b',r,'join')
 def test_invalid_mode_and_size(self):
  for mode,size in [('bad',1),('arena',4),('arena',True)]:
   with self.assertRaises(Rejected):self.create(mode=mode,size=size)
 def wager(self,size=1):
  r=self.m.call('a','create',dict(mode='arena',team_size=size,character='hero',wager=True))['lobby']
  for n in range(1,size*2):self.act(str(n),r,'join')
  for uid in self.m.rooms[r['id']]['members']:
   self.act(uid,r,'stake',item=dict(base='sword',uid='unique-item-'+uid,name='Sword '+uid))
  for uid in self.m.rooms[r['id']]['members']:self.act(uid,r,'ready',ready=True)
  return r
 def finish(self,r,winner):
  self.act('a',r,'start');rr=self.m.rooms[r['id']]
  return self.m.worker(r['id'],rr['worker_key'],'state',dict(state='finished',winner=winner))
 def test_stakes_transfer_only_after_result(self):
  r=self.wager();self.assertEqual(self.m.call('a','receipts',{})['receipts'],[])
  self.finish(r,0)
  win=self.m.call('a','receipts',{})['receipts'];lose=self.m.call('1','receipts',{})['receipts']
  self.assertEqual(len(win[0]['items']),2);self.assertEqual(lose[0]['items'],[])
 def test_team_rewards_split_without_duplicates(self):
  r=self.wager(3);self.finish(r,1)
  rewards=[it['uid'] for v in self.m.receipts.values() for it in v['items']]
  self.assertEqual(len(rewards),6);self.assertEqual(len(set(rewards)),6)
  for uid in ['3','4','5']:self.assertEqual(len(self.m.call(uid,'receipts',{})['receipts'][0]['items']),2)
 def test_retry_stake_preserves_consent(self):
  r=self.wager();item=self.m.rooms[r['id']]['members']['a']['stake']
  self.act('a',r,'stake',item=item)
  self.assertTrue(all(m['ready'] for m in self.m.rooms[r['id']]['members'].values()))
 def test_result_replay_does_not_award_twice(self):
  r=self.wager();self.finish(r,0);rr=self.m.rooms[r['id']]
  self.m.worker(r['id'],rr['worker_key'],'state',dict(state='finished',winner=1))
  self.assertEqual(len(self.m.receipts),2);self.assertEqual(len(self.m.call('a','receipts',{})['receipts'][0]['items']),2)
 def test_leave_refunds_and_resets_other_consent(self):
  r=self.wager();self.act('a',r,'leave')
  self.assertEqual(len(self.m.call('a','receipts',{})['receipts'][0]['items']),1)
  self.assertFalse(self.m.rooms[r['id']]['members']['1']['ready'])
 def test_timeout_refunds(self):
  r=self.wager();self.act('a',r,'start');self.now+=181;self.m.sweep()
  self.assertEqual([len(v['items']) for v in self.m.receipts.values()],[1,1])
 def test_restart_refunds_once(self):
  r=self.wager();self.act('a',r,'start')
  for _ in range(2):
   other=Lobbies(str(Path(self.temp.name)/'state.sqlite'),self.launch,self.stopped.append)
   self.assertEqual([len(v['items']) for v in other.receipts.values()],[1,1]);other.db.close()
 def test_draw_refunds(self):
  r=self.wager();self.finish(r,-1)
  self.assertEqual([len(v['items']) for v in self.m.receipts.values()],[1,1])
 def test_receipts_private_and_ack_persistent(self):
  r=self.wager();self.finish(r,0);receipt=self.m.call('a','receipts',{})['receipts'][0]
  with self.assertRaises(Rejected):self.m.call('1','ack',dict(receipt=receipt['id']))
  self.m.call('a','ack',dict(receipt=receipt['id']))
  self.assertEqual(self.m.call('a','receipts',{})['receipts'],[])
  self.assertEqual(self.m.call('stranger','receipts',{})['receipts'],[])
 def test_stake_cannot_change_after_consent(self):
  r=self.wager()
  with self.assertRaises(Rejected):self.act('a',r,'stake',item=dict(base='sword',uid='different-unique'))
 def test_stake_required_before_ready(self):
  r=self.m.call('a','create',dict(mode='arena',character='hero',wager=True))['lobby']
  with self.assertRaises(Rejected):self.act('a',r,'ready',ready=True)
 def test_no_stakes_in_other_modes(self):
  with self.assertRaises(Rejected):self.m.call('a','create',dict(mode='waves',character='hero',wager=True))
 def test_late_join_gets_unique_ticket(self):
  r=self.create(mode='waves');self.act('a',r,'ready',ready=True);self.act('a',r,'start');rr=self.m.rooms[r['id']]
  self.m.worker(r['id'],rr['worker_key'],'state',dict(state='playing',joinable=True))
  self.act('b',r,'join');ticket=rr['members']['b']['ticket']
  self.assertEqual(self.m.worker(r['id'],rr['worker_key'],'redeem',dict(ticket=ticket))['user'],'b')
 def test_arena_late_join_never_allowed(self):
  r=self.pair();self.act('a',r,'start');rr=self.m.rooms[r['id']]
  self.m.worker(r['id'],rr['worker_key'],'state',dict(state='playing',joinable=True))
  self.assertFalse(self.m.public(rr,'x')['joinable'])
 def test_character_path_traversal_rejected(self):
  with self.assertRaises(Rejected):self.m.call('a','create',dict(mode='waves',character='../hero'))
 def test_departed_account_can_join_another_match(self):
  r=self.pair();self.act('a',r,'start');rr=self.m.rooms[r['id']]
  self.m.worker(r['id'],rr['worker_key'],'depart',dict(user='a'))
  new=self.create('a','waves');self.assertNotEqual(new['id'],r['id'])
  self.assertIn('a',rr['members']) # Retained for arena settlement.
 def test_client_polling_does_not_hide_stalled_worker(self):
  r=self.pair();self.act('a',r,'start');rr=self.m.rooms[r['id']]
  self.m.worker(r['id'],rr['worker_key'],'state',dict(state='playing'))
  self.now+=45;self.act('a',r,'get');self.now+=16;self.m.sweep()
  self.assertEqual(rr['state'],'aborted')
 def test_leaver_opens_active_wave_slot(self):
  r=self.create(mode='waves');self.act('a',r,'ready',ready=True);self.act('a',r,'start');rr=self.m.rooms[r['id']]
  self.m.worker(r['id'],rr['worker_key'],'state',dict(state='playing',joinable=True))
  for uid in ['b','c','d']:self.act(uid,r,'join')
  with self.assertRaises(Rejected):self.act('e',r,'join')
  self.m.worker(r['id'],rr['worker_key'],'depart',dict(user='b'))
  self.act('e',r,'join');self.assertEqual(self.m.public(rr,'a')['joined'],4)

class LaunchRoomTests(unittest.TestCase):
 """Service.launch: no slot count; room = this mode's measured cost against free memory, the CPU budget and ports."""
 def make(self,cpus=2,mem_mb=4000,ports=16):
  import service,types
  svc=service.Service.__new__(service.Service)
  svc.args=types.SimpleNamespace(min_free_mb=300,cpu_budget=0.9,reserve_cpu=0.3,first_port=24600,ports=ports,port=7352,
   server_binary='/usr/bin/true',godot='godot',game='.',public_host='127.0.0.1')
  svc.processes={};svc.root=Path(tempfile.mkdtemp())
  svc.cpus=lambda:cpus;svc.mem_available_mb=lambda:mem_mb
  return svc
 def room(self,rid,mode='battlegrounds'):return {'id':rid,'mode':mode,'team_size':1,'capacity':16,'worker_key':'k','members':{}}
 def fill(self,svc,mode,tries=40):
  n=0
  try:
   for i in range(tries):
    svc.launch(self.room('r%d'%i,mode));n+=1
    import time;time.sleep(0)   # (a finished /usr/bin/true no longer counts as running: keep them alive)
  except Rejected as e:self.assertIn('full',str(e))
  return n
 def test_cpu_budget_fills_then_full(self):
  svc=self.make(cpus=2)
  svc.processes={}
  import service
  real=service.subprocess.Popen
  class Alive:
   def __init__(s,*a,**k):pass
   def poll(s):return None
  service.subprocess.Popen=Alive
  self.addCleanup(lambda:setattr(service.subprocess,'Popen',real))
  self.assertEqual(self.fill(svc,'battlegrounds'),5)        # (2 x 0.9 - 0.3) / 0.3 per Battlegrounds world
 def test_memory_short_is_full(self):
  svc=self.make(mem_mb=600)
  with self.assertRaises(Rejected):svc.launch(self.room('a'))
 def test_bigger_machine_holds_more(self):
  svc=self.make(cpus=8,mem_mb=16000,ports=32)
  import service
  real=service.subprocess.Popen
  class Alive:
   def __init__(s,*a,**k):pass
   def poll(s):return None
  service.subprocess.Popen=Alive
  self.addCleanup(lambda:setattr(service.subprocess,'Popen',real))
  self.assertEqual(self.fill(svc,'arena'),32)               # ports are the limit here: (8 x 0.9 - 0.3) / 0.15 = 46
