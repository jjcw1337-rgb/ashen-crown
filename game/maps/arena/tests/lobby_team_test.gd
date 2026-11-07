extends SceneTree
## Run 2*N clients with -- N INDEX against the local broker, N=2 or 3, INDEX=0..2*N-1.
var g
var team_size:=2
var index:=0
var checks:=0
var fails:=0
func _initialize():
 var args:=OS.get_cmdline_user_args()
 team_size=int(args[0]);index=int(args[1])
 node_added.connect(func(n):
  if n is SubViewport:n.disable_3d=true)
 load("res://scripts/build_env.gd").forced={"env":"local","cloud":"0","lobby_url":"http://127.0.0.1:7352"}
 g=load("res://main.tscn").instantiate();g.char_dir="user://lobby_team_%d_%d/"%[team_size,index]
 root.disable_3d=true;root.add_child(g);run()
func check(ok: bool,label: String):
 checks+=1;print("[TEAM-",index,"] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func until(test: Callable,seconds:=180.0) -> bool:
 var end:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  g._intro_skip=true
  if test.call():return true
  await process_frame
 return false
func run():
 Engine.max_fps=20
 if not await until(func():return g.world!=null and not g._busy and not g._intro_playing):quit(1);return
 await g.start_game(false,"knight","","Team %d"%index)
 g.hero.gold=4321;g.save_game();var character:String=g.char_id
 var client=g.lobby_client
 client.auth="Bearer dev-team-%d-%d"%[team_size,index];client.identity=client.auth.sha256_text().substr(0,24)
 client.open("arena");await create_timer(1).timeout
 if index==0:await client.action("create",{"mode":"arena","team_size":team_size,"name":"Team %d Test"%team_size})
 else:
  if not await until(func():return client.rooms.any(func(r):return r.name=="Team %d Test"%team_size)):quit(1);return
  for r in client.rooms:
   if r.name=="Team %d Test"%team_size:await client.action("join",{"id":r.id});break
 if not await until(func():return client.room.get("members",{}).size()==team_size*2):quit(1);return
 check(true,"all players share one lobby")
 await client.action("ready",{"ready":true})
 if index==0:
  if not await until(func():return client.room.members.values().all(func(m):return m.ready)):quit(1);return
  await client.action("start")
 if not await until(func():return g.net.welcomed and not g.net.loading and not g._busy and g.arena_state.get("phase","")=="fight"):quit(1);return
 check(g.net.players.size()==team_size*2-1,"all teammates and opponents connected")
 var my_team:int=g.arena_state.teams.get(str(g.net.multiplayer.get_unique_id()),-1)
 check(my_team in [0,1],"server assigns a team")
 if my_team==0:
  for round_index in 2:
   if not await until(func():return g.arena_state.get("phase","")=="fight",30):quit(1);return
   var end:=Time.get_ticks_msec()+12000
   while Time.get_ticks_msec()<end and g.arena_state.get("phase","")=="fight":
    for pid in g.net.players:
     if int(g.arena_state.teams.get(str(pid),-1))!=my_team:g.net.send_pvp_hit(pid,5000,g.hero.global_position)
    await create_timer(0.3).timeout
   check(g.arena_state.get("phase","")!="fight","team round resolves")
 check(await until(func():return not g.playing and g.ui.title_panel.visible,90),"match ends and returns home")
 var saved=JSON.parse_string(FileAccess.get_file_as_string(g.char_dir+character+".json"))
 check(int(saved.hero.gold)==4321,"casual team arena preserves character")
 client.panel.hide();client.room={}
 # Stop polling before teardown, then let any in-flight HTTP/result work finish.
 await until(func():return not client.polling and not client.busy and not client._returning,15)
 await create_timer(10).timeout
 g.queue_free()
 for i in 30:await process_frame
 print("[TEAM-",index,"] done ",checks," checks / ",fails," failures");quit(1 if fails else 0)
