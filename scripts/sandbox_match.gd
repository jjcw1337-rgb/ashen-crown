extends "res://scripts/arena_match.gd"
## Practice uses existing authenticated PvP transport, without rounds, loot, stakes or survivor writes.
## Each peer is its own team. Solo bots live in Sandbox; this worker never spawns client-only bots.
var respawns := {}

func team(pid: int) -> int:
 return pid if game.match_instance.members.has(pid) else -1

func begin_round() -> void:
 round_phase="fight"
 state="raid"
 send_state()

func send_state() -> void:
 var teams:={}
 for pid in game.net.players:teams[str(pid)]=team(pid)
 game.net.rpc("cl_arena_state",{"phase":round_phase,"round":0,"scores":[0,0],"left":0,"teams":teams,"practice":true})

func _process(delta: float) -> void:
 if game==null or game._busy or game.match_instance==null:return
 park_hero()
 if not game.match_instance.begun or game.match_instance.ending:return
 raid_t+=delta
 sync_t-=delta
 if sync_t<=0:sync_t=0.5;send_state()
 for pid in respawns.keys():
  if not game.net.players.has(pid):respawns.erase(pid)
 for pid in game.net.players:
  var h=game.net.players[pid].hero
  if not h.dead:
   respawns.erase(pid)
   continue
  respawns[pid]=float(respawns.get(pid,0.0))+delta
  if respawns[pid]>=Sandbox.RESPAWN:
   respawns[pid]=0.0
   var at:Vector3=game.match_instance.spawn(pid)
   h.dead=false;h.life=h.max_life;h.global_position=at;h.net_pos=at
   cc_dr.erase(pid)
   game.net.rpc_id(pid,"cl_arena_reset",at)
