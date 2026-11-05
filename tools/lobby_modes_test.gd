extends SceneTree
## Start one-player wave and raid lobbies through the real broker. Isolated disposable heroes.
var g
var fails:=0
var checks:=0
func _initialize():
 node_added.connect(func(n):
  if n is SubViewport:n.disable_3d=true)
 load("res://scripts/build_env.gd").forced={"cloud":"0","lobby_url":"http://127.0.0.1:7352"}
 g=load("res://main.tscn").instantiate();g.char_dir="user://lobby_modes_test/";root.disable_3d=true;root.add_child(g);run()
func check(ok: bool,label: String):
 checks+=1;print("[MODES] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func until(test: Callable,seconds:=120.0) -> bool:
 var end:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  g._intro_skip=true
  if test.call():return true
  await process_frame
 return false
func run():
 Engine.max_fps=30
 await until(func():return g.world!=null and not g._busy and not g._intro_playing)
 var client=g.lobby_client
 client.auth="Bearer dev-modes";client.identity=client.auth.sha256_text().substr(0,24)
 for mode in (["battlegrounds"] if OS.get_cmdline_user_args().has("bg") else ["waves","battlegrounds"]):
  await g.start_game(false,"knight","","Lobby "+mode)
  var character:String=g.char_id
  client.open(mode)
  await client.action("create",{"mode":mode,"name":"Mode "+mode})
  check(client.room.get("state","")=="waiting",mode+" waits until started")
  var id:String=client.room.id
  await client.action("ready",{"ready":true})
  await client.action("start")
  check(await until(func():return g.net.welcomed and not g.net.loading and not g._busy and g.cur_zone==("vigil" if mode=="waves" else "bg")),mode+" admission and destination")
  check(g.char_id==character,mode+" uses selected hero")
  if mode=="waves":
   check(await until(func():return g.world.has_meta("vigil") and g.world.get_meta("vigil").state in ["count","wave","break"],30),"waves kindle automatically from lobby")
  else:
   check(await until(func():return not g.bg_raid.is_empty(),30),"raid state reaches the client")
  var result:Dictionary=await client.request("get",{"id":id})
  for attempt in 15:
   if result.get("lobby",{}).get("state","")=="playing":break
   await create_timer(1).timeout
   result=await client.request("get",{"id":id})
  check(result.get("lobby",{}).get("state","")=="playing",mode+" worker reports active")
  await create_timer(40 if OS.get_cmdline_user_args().has("late") else 11).timeout
  result=await client.request("get",{"id":id})
  check(result.get("lobby",{}).get("joinable",false),mode+" active game remains joinable during entry window")
  await g.exit_to_title()
  await create_timer(24).timeout
  result=await client.request("get",{"id":id})
  check(result.get("lobby",{}).get("state","")=="finished",mode+" empty instance closes")
 client.panel.hide();client.room={};g.queue_free()
 for i in 30:await process_frame
 print("[MODES] done ",checks," checks / ",fails," failures");quit(1 if fails else 0)
