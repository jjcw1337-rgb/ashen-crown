extends SceneTree
## Deterministic team and round rules. Socket admission/hits are covered by lobby_game_test.gd.
class Fighter extends Node3D:
 var dead:=false
 var life:=100.0
 var max_life:=100.0
 var net_pos:=Vector3.ZERO
 var phased:=false
class MockGame extends Node:
 var _busy:=false
 var net
 var match_instance
 var hero
 var world
class Transport extends RefCounted:
 var players:={}
 func rpc(_method,_data):pass
 func rpc_id(_pid,_method,_at):pass
class Instance extends RefCounted:
 var members:={}
 var begun:=true
 var ending:=false
 var result:={}
 func spawn(pid):return Vector3(-2 if members[pid].team==0 else 2,0,0)
 func finish(state,reason,winner=-1):ending=true;result={"state":state,"winner":winner,"reason":reason}
var fails:=0
var checks:=0
func _initialize():call_deferred("run")
func check(ok: bool,label: String):
 checks+=1;print("[ARENA] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func run():
 var script=load("res://game/maps/arena/arena_match.gd")
 for size in [1,2,3]:
  var arena=script.new();root.add_child(arena);arena.set_process(false)
  var transport=Transport.new();var instance=Instance.new();var parked=Fighter.new();root.add_child(parked)
  var game=MockGame.new();root.add_child(game);game.net=transport;game.match_instance=instance;game.hero=parked;game.world={"bounds":Rect2(-20,-20,40,40)};arena.game=game
  for pid in range(1,size*2+1):
   var h=Fighter.new();root.add_child(h)
   instance.members[pid]={"team":0 if pid<=size else 1}
   transport.players[pid]={"hero":h}
  arena.begin_round()
  check(arena.pvp_pair(1,size+1).is_empty(),"warmup rejects damage "+str(size)+"v"+str(size))
  arena._process(5.1)
  check(arena.pvp_pair(1,size+1).size()==2,"enemy damage allowed during fight")
  if size>1:check(arena.pvp_pair(1,2).is_empty(),"friendly fire rejected")
  for round_index in 2:
   for pid in transport.players:
    if instance.members[pid].team==1:transport.players[pid].hero.dead=true
   arena._process(0.1)
   check(arena.scores[0]==round_index+1,"team elimination awards one round")
   if round_index==0:
    arena._process(5.1)
    check(transport.players.values().all(func(p):return not p.hero.dead and p.hero.life==100),"next round resets every fighter")
    arena._process(5.1)
  check(instance.ending and instance.result.winner==0,"first two round wins ends match")
  # Timeout decides by surviving team health; exact ties do not invent a winner.
  instance.ending=false;arena.scores=[0,0];arena.round_no=0;arena.begin_round();arena._process(5.1)
  for pid in transport.players:
   if instance.members[pid].team==1:transport.players[pid].hero.life=50
  arena._process(181)
  check(arena.scores[0]==1,"timeout compares team health")
  arena.scores=[0,0];arena.round_no=6;arena.begin_round();arena._process(5.1);arena._process(181)
  check(instance.ending and instance.result.winner==-1,"repeated ties draw and refund")
  for p in transport.players.values():p.hero.queue_free()
  parked.queue_free();game.queue_free();arena.game=null;arena.queue_free()
  await process_frame
 print("[ARENA] done ",checks," checks / ",fails," failures");quit(1 if fails else 0)
