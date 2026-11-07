extends SceneTree
## Mode-specific solo entry, temporary characters, and repeated exit/class-change cleanup.
var g
var failures := 0
func _initialize() -> void:
 BuildEnv.forced={"env":"local","cloud":"0"}
 call_deferred("run")
func _process(_dt: float) -> bool:
 if is_instance_valid(g):g._intro_skip=true
 return false
func check(ok: bool, label: String) -> void:
 print("[SANDBOX ENTRY] ","ok " if ok else "FAIL ",label)
 if not ok:failures+=1
func run() -> void:
 g=load("res://main.tscn").instantiate()
 g.char_dir="user://sandbox_entry_test/"
 g.old_save="user://sandbox_entry_test/absent.json"
 root.add_child(g);current_scene=g
 while g._busy or g.world==null or not g.ui.title_panel.visible:await process_frame
 var lobby=g.lobby_client
 lobby.set_process(false)
 lobby.panel.show()
 var mode=load("res://scripts/mp_mode.gd")
 var original_count: int=g.list_characters().size()
 for name in mode.MODES:
  lobby.selected_mode=name;lobby.draw()
  check((is_instance_valid(lobby.solo_button) and lobby.solo_button.is_visible_in_tree())==(name=="sandbox"),"solo belongs only to selected Sandbox: "+name)
 check(mode.solo_label("waves")=="","retired Waves has no solo action")
 g.dev_tools=false
 lobby.selected_mode="sandbox"
 lobby.run_class="plague"
 await lobby.play_solo()
 check(g.sandbox!=null and g.cur_zone=="sandbox" and g.playing,"solo works from title without admin or saved character")
 check(not g.net.active and lobby.match_id=="" and lobby.room.is_empty(),"solo needs no network/lobby worker")
 check(g.hero.cls=="plague" and g.hero.level==20 and g.char_id=="","temporary selected class")
 check(not g.can_autosave(),"practice cannot autosave")
 g.save_game()
 check(g.list_characters().size()==original_count,"practice does not create a saved hero")
 # A roster switch while delayed effects are alive exercises the shared callback/cleanup contracts.
 for cls in ["serpent","wyvern","warlock"]:
  load("res://game/maps/arena/sandbox.gd").outfit(g,g.hero,cls,20,"geared")
  for ev in SkillWarmData.EVENTS.get(cls,[]):
   if ev is Dictionary:SkillFx.play(g.hero,SkillWarm._rebuild(ev,g.hero.global_position))
  for i in 3:await physics_frame
 await g.close_sandbox()
 lobby.set_process(false)
 check(not g.playing and g.sandbox==null and g.char_id=="","leaving title-started practice returns to title")
 check(g.list_characters().size()==original_count,"no practice character persisted after exit")
 for i in 2:
  await g.open_sandbox("archer")
  var sandbox=g.sandbox
  for cls in ["demon","plague","archer","serpent","wyvern"]:sandbox.spawn_bot(cls,20,"geared")
  check(sandbox.bots.size()==5 and sandbox.spawn_bot("knight",20,"geared")==null,"six-actor bound prevents accidental unbounded spawns")
  sandbox.ffa=true
  sandbox.spawn_pack("zombie",5)
  for frame in 120:await physics_frame
  await g.close_sandbox()
  lobby.set_process(false)
  for frame in 8:await process_frame
  check(root.find_children("Bot*","Node3D",true,false).is_empty(),"repeated mixed practice leaves no bots")
 g.queue_free()
 for i in 12:await process_frame
 print("[SANDBOX ENTRY] done, %d failed"%failures)
 quit(1 if failures else 0)
