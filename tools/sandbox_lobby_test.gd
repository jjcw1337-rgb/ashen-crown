extends SceneTree
## Two clients against an isolated --dev broker. Start host, then guest; never use a live endpoint.
## -- host|guest --broker-url http://127.0.0.1:7354 [--run-id unique] [--capture absolute.png]
var g
var role := "host"
var broker := ""
var run_id := "sandbox-local"
var capture := ""
var failures := 0
var checks := 0
func _initialize() -> void:
 var args:=OS.get_cmdline_user_args()
 role=args[0] if not args.is_empty() else "host"
 if args.has("--broker-url"):broker=args[args.find("--broker-url")+1]
 if args.has("--run-id"):run_id=args[args.find("--run-id")+1]
 if args.has("--capture"):capture=args[args.find("--capture")+1]
 if role not in ["host","guest"] or not broker.begins_with("http://127.0.0.1:"):
  printerr("Sandbox fixture requires host/guest and an explicit loopback broker");quit(2);return
 load("res://scripts/build_env.gd").forced={"env":"local","cloud":"0","lobby_url":broker}
 call_deferred("run")
func _process(_delta: float) -> bool:
 if is_instance_valid(g):g._intro_skip=true
 return false
func check(ok: bool,label: String) -> void:
 checks+=1
 print("[SANDBOX LOBBY ",role,"] ","ok " if ok else "FAIL ",label)
 if not ok:failures+=1
func until(test: Callable,seconds:=180.0) -> bool:
 var end:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<end:
  if test.call():return true
  await process_frame
 return false
func run() -> void:
 Engine.max_fps=30
 g=load("res://main.tscn").instantiate()
 g.char_dir="user://sandbox_lobby_test_"+role+"/"
 g.old_save=g.char_dir+"absent.json"
 root.add_child(g);current_scene=g
 if not await until(func():return g.world!=null and not g._busy and not g._intro_playing):quit(1);return
 # Preserve an actual story character byte-for-byte across online practice.
 await g.start_game(false,"knight","","Practice Save Probe")
 g.hero.gold=4321;g.save_game()
 var save_path:String=g.char_dir+g.char_id+".json"
 await g.exit_to_title()
 var before:=FileAccess.get_file_as_string(save_path)
 var client=g.lobby_client
 client.auth="Bearer dev-"+run_id+"-"+role
 client.identity=client.auth.sha256_text().substr(0,24)
 client.run_class="plague" if role=="host" else "archer"
 client.open("sandbox")
 if role=="host":
  await client.action("create",{"mode":"sandbox","name":run_id})
  check(not client.room.is_empty(),"host creates practice without a survivor")
  if client.room.is_empty():quit(1);return
  await client.action("ready",{"ready":true})
  await client.action("start")
 else:
  if not await until(func():return client.rooms.any(func(r):return r.name==run_id and r.state=="playing" and r.joinable)):quit(1);return
  for room in client.rooms:
   if room.name==run_id:await client.action("join",{"id":room.id});break
 if not await until(func():return g.net.welcomed and not g.net.loading and not g._busy and g.arena_state.get("phase","")=="fight"):quit(1);return
 check(g.sandbox!=null and g.sandbox.online and g.cur_zone=="sandbox","hosted practice reaches the Sandbox world")
 check(not g.can_autosave(),"practice cannot autosave")
 check(await until(func():return g.net.players.size()==1),"second player joins an already running practice")
 check(g.sandbox.spawn_bot("knight",20,"geared")==null,"hosted mode does not create unsynchronized local bots")
 if g.net.players.size()==1:
  var peer:int=g.net.players.keys()[0]
  g.hero.global_position=Vector3(-2 if role=="host" else 2,0,0)
  if role=="host":
   var victim=g.net.players[peer].hero
   await create_timer(2).timeout
   var end:=Time.get_ticks_msec()+15000
   while Time.get_ticks_msec()<end and not victim.dead:
    g.net.send_pvp_hit(peer,5000,g.hero.global_position)
    await create_timer(0.25).timeout
   check(victim.dead,"server accepts free-for-all player damage")
   check(await until(func():return not victim.dead,15),"opponent automatically respawns")
  else:
   check(await until(func():return g.hero.dead,25),"received player damage can kill the temporary hero")
   check(await until(func():return not g.hero.dead,15),"server respawns the local hero")
   check(g.hero.life>0 and g.arena_state.get("phase","")=="fight","practice continues after death without a round result")
 if capture!="" and DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png(capture)
 await create_timer(2).timeout
 await g.close_sandbox()
 check(not g.playing and not g.net.active and g.sandbox==null,"leaving practice closes transport and returns home")
 check(FileAccess.get_file_as_string(save_path)==before,"saved story character remains byte-identical")
 check(not FileAccess.file_exists(g.char_dir+"sandbox_"+client.run_class+".json"),"no practice save created")
 client.panel.hide();client.set_process(false)
 await until(func():return not client.polling and not client.busy,15)
 await create_timer(10).timeout
 g.queue_free()
 for i in 12:await process_frame
 print("[SANDBOX LOBBY ",role,"] done ",checks," checks / ",failures," failures")
 quit(1 if failures else 0)
