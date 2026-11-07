extends SceneTree
## Two clients through the actual HTTP lobby service and disposable ENet arena worker.
## Run service.py --dev on loopback, then this script with -- a and -- b (isolated saves).
var g
var role := "a"
var fails := 0
var checks := 0
var wager:=false
func _initialize():
 node_added.connect(func(n):
  if n is SubViewport:n.disable_3d=true)
 role="b" if OS.get_cmdline_user_args().has("b") else "a"
 wager=OS.get_cmdline_user_args().has("wager")
 load("res://scripts/build_env.gd").forced={"env":"local","cloud":"0","lobby_url":"http://127.0.0.1:7352"}
 g=load("res://main.tscn").instantiate();g.char_dir="user://lobby_test_"+role+"/"
 root.disable_3d=true;root.add_child(g);run()
func check(ok: bool,label: String):
 checks+=1;print("[LOBBY-",role,"] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func until(test: Callable,seconds:=90.0) -> bool:
 var end:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  g._intro_skip=true
  if test.call():return true
  await process_frame
 return false
func shot(name: String):
 if DisplayServer.get_name()=="headless":return
 root.disable_3d=false
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/lobby-"+name+".png")
 root.disable_3d=true
func run():
 Engine.max_fps=30
 check(await until(func():return g.world!=null and not g._busy and not g._intro_playing),"post-intro home ready")
 await g.start_game(false,"knight","","Lobby "+role)
 g.hero.gold=1234
 if wager:g.hero.inventory[0]=load("res://game/items/items.gd").make("short_sword")
 g.save_game()
 var character:String=g.char_id
 var client=g.lobby_client
 client.auth="Bearer dev-"+role;client.identity=client.auth.sha256_text().substr(0,24)
 client.open("arena")
 await create_timer(1).timeout
 if role=="a":
  await client.action("create",{"mode":"arena","team_size":1,"name":"Arena Test","wager":wager})
 else:
  check(await until(func():return not client.rooms.is_empty()),"shared list discovers created lobby")
  if not client.rooms.is_empty():await client.action("join",{"id":client.rooms[0].id})
 check(await until(func():return client.room.get("members",{}).size()==2),"two players in same waiting lobby")
 if wager:
  await client._commit_stake(0)
  check(await until(func():return client.room.members.values().all(func(m):return m.has("stake"))),"both selected stakes locked")
 await client.action("ready",{"ready":true})
 if role=="a":
  await shot("waiting")
  check(await until(func():return client.room.members.values().all(func(m):return m.ready)),"both Ready")
  await client.action("start")
 check(await until(func():return g.net.is_client() and g.net.welcomed and not g.net.loading and not g._busy and g.cur_zone=="arena",120),"ticket handoff into arena")
 check(g.arena_mode and g.char_id==character and g.hero.gold==1234,"same character preserved")
 check(await until(func():return g.net.players.size()==1),"opponent present")
 check(await until(func():return g.arena_state.get("phase","")=="fight",30),"round begins after countdown")
 if role=="a":
  await shot("fight")
  for round_index in 2:
   check(await until(func():return g.arena_state.get("phase","")=="fight",30),"fight phase round "+str(round_index+1))
   var end:=Time.get_ticks_msec()+12000
   while Time.get_ticks_msec()<end and g.arena_state.get("phase","")=="fight":
    for pid in g.net.players:g.net.send_pvp_hit(pid,5000,g.hero.global_position)
    await create_timer(0.2).timeout
   check(g.arena_state.get("phase","")!="fight","round resolves from real PvP damage")
 check(await until(func():return not g.playing and g.ui.title_panel.visible,90),"match finishes and returns home")
 var saved=JSON.parse_string(FileAccess.get_file_as_string(g.char_dir+character+".json"))
 check(int(saved.hero.gold)==1234,"arena keeps character gold")
 if wager:
  await create_timer(5).timeout
  await client.collect()
  saved=JSON.parse_string(FileAccess.get_file_as_string(g.char_dir+character+".json"))
  var swords:int=saved.hero.inventory.filter(func(it):return it is Dictionary and it.get("base","")=="short_sword").size()
  check(swords==(2 if role=="a" else 0),"winner receives the two staked items; loser receives none")
 await create_timer(10).timeout
 client.panel.hide();client.room={}
 g.net.shutdown();g.queue_free()
 for i in 30:await process_frame
 print("[LOBBY-",role,"] done ",checks," checks / ",fails," failures")
 quit(1 if fails else 0)
