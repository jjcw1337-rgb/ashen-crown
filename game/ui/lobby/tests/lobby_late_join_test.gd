extends SceneTree
## Run alongside lobby_modes_test.gd -- late. Joins each already-playing mode with a second account.
var g
var checks:=0
var fails:=0
func _initialize():
 load("res://game/systems/net/build_env.gd").forced={"env":"local","cloud":"0","lobby_url":"http://127.0.0.1:7352"}
 g=load("res://main.tscn").instantiate();g.char_dir="user://lobby_late_join/";root.add_child(g);run()
func check(ok: bool,label: String):
 checks+=1;print("[LATE] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func until(test: Callable,seconds:=240.0) -> bool:
 var end:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  g._intro_skip=true
  if test.call():return true
  await process_frame
 return false
func run():
 Engine.max_fps=20
 if not await until(func():return g.world!=null and not g._busy and not g._intro_playing):quit(1);return
 var c=g.lobby_client;c.auth="Bearer dev-modes-guest";c.identity=c.auth.sha256_text().substr(0,24)
 for mode in ["battlegrounds"]:
  await g.start_game(false,"knight","","Late Joiner")
  c.open(mode)
  var found:=await until(func():return c.rooms.any(func(r):return r.mode==mode and r.state=="playing" and r.joinable))
  check(found,"running "+mode+" discoverable")
  if not found:quit(1);return
  for r in c.rooms:
   if r.mode==mode and r.state=="playing" and r.joinable:await c.action("join",{"id":r.id});break
  check(await until(func():return g.net.welcomed and not g.net.loading and not g._busy and g.cur_zone=="bg",90),mode+" late admission succeeds")
  check(g.net.players.size()==1,mode+" joins the existing player's world")
  await create_timer(2).timeout
  await g.exit_to_title()
 await create_timer(10).timeout
 c.panel.hide();c.room={};g.queue_free()
 for i in 30:await process_frame
 print("[LATE] done ",checks," checks / ",fails," failures");quit(1 if fails else 0)
