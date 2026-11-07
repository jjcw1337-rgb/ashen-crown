extends Battlegrounds
## Team elimination, first to two wins. Ordinary arena never drops or strips equipment.
var scores := [0,0]
var round_no := 0
var round_t := 0.0
var round_phase := "waiting"
var gap := 0.0
var sync_t := 0.0

func team(pid: int) -> int:
 return int(game.match_instance.members.get(pid,{}).get("team",-1))
func pvp_pair(attacker: int,target: int) -> Array:
 if round_phase!="fight" or team(attacker)<0 or team(attacker)==team(target):return []
 return super.pvp_pair(attacker,target)
func pvp_obj_hit(attacker: int,owner_pid: int,oid: int,from: Vector3) -> void:
 if round_phase=="fight" and team(attacker)!=team(owner_pid):super.pvp_obj_hit(attacker,owner_pid,oid,from)
func died(_pid: int,_items: Array,_at: Vector3) -> void:pass
func player_left(_pid: int,_at: Vector3) -> void:pass
func picked(_pid: int,_it: Dictionary) -> void:pass
func admin_cmd(_pid: int,_cmd: String) -> void:pass
func begin_round() -> void:
 round_no+=1
 round_phase="countdown";state="lobby";gap=5.0;round_t=0.0
 cc_dr.clear();last_hit.clear();pvp_effect_t.clear();pvp_obj_last.clear()
 for pid in game.net.players:
  var at:Vector3=game.match_instance.spawn(pid)
  var h=game.net.players[pid].hero
  h.dead=false;h.life=h.max_life;h.global_position=at;h.net_pos=at
  game.net.rpc_id(pid,"cl_arena_reset",at)
 send_state()
func send_state() -> void:
 var teams:={}
 for pid in game.match_instance.members:teams[str(pid)]=team(pid)
 game.net.rpc("cl_arena_state",{"phase":round_phase,"round":round_no,"scores":scores,"left":gap if round_phase!="fight" else maxf(0,180-round_t),"teams":teams})
func _process(delta: float) -> void:
 if game==null or game._busy or game.match_instance==null:return
 park_hero()
 if not game.match_instance.begun or game.match_instance.ending:return
 raid_t+=delta
 sync_t-=delta
 if sync_t<=0:sync_t=0.5;send_state()
 if round_phase=="countdown":
  gap-=delta
  if gap<=0:round_phase="fight";state="raid";send_state()
 elif round_phase=="break":
  gap-=delta
  if gap<=0:begin_round()
 elif round_phase=="fight":
  round_t+=delta
  var living:=[0,0]
  var health:=[0.0,0.0]
  for pid in game.net.players:
   var h=game.net.players[pid].hero
   var t:=team(pid)
   if t>=0 and not h.dead:
    living[t]+=1;health[t]+=h.life/maxf(h.max_life,1)
  var winner:=-2
  if living[0]==0 or living[1]==0:winner=-1 if living[0]==living[1] else (0 if living[0]>0 else 1)
  elif round_t>=180:winner=-1 if is_equal_approx(health[0],health[1]) else (0 if health[0]>health[1] else 1)
  if winner!=-2:
   if winner>=0:scores[winner]+=1
   round_phase="break";state="lobby";gap=5
   if scores[0]>=2 or scores[1]>=2:
    round_phase="finished";send_state()
    game.match_instance.finish("finished","Team %s wins %d–%d!" % ["Ember" if scores[0]>scores[1] else "Frost",scores[0],scores[1]],0 if scores[0]>scores[1] else 1)
   elif round_no>=7:
    round_phase="finished";game.match_instance.finish("finished","Arena drawn after repeated tied rounds.")
   else:send_state()
