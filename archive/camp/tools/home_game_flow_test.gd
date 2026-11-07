extends SceneTree
## Rendered home/subpage/entry regression checks, using isolated characters and no public server.
var g
var fails := 0
func _initialize():
 load("res://game/systems/net/build_env.gd").forced={"env":"staging","cloud":"0"}
 g=load("res://main.tscn").instantiate()
 g.char_dir="user://flow_review/"
 g.old_save=g.char_dir+"none.json"
 DirAccess.make_dir_recursive_absolute(g.char_dir)
 FileAccess.open(g.char_dir+".adopted",FileAccess.WRITE).close()
 root.add_child(g)
 run()
func frames(n=12):
 for i in n:await process_frame
func check(ok:bool,label:String):
 print("[FLOW] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func until(condition:Callable):
 var end=Time.get_ticks_msec()+60000
 while not condition.call() and Time.get_ticks_msec()<end:await process_frame
 return condition.call()
func rect(c:Control)->Rect2:
 return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO,c.size)
func inside(c:Control)->bool:
 return Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(rect(c))
func shot(label):
 if DisplayServer.get_name()=="headless":return
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/flow-"+label+".png")
func run():
 Engine.max_fps=30
 while g.ui==null or g._busy or g._intro_playing:
  g._intro_skip=true
  await process_frame
 var ui=g.ui
 root.mode=Window.MODE_WINDOWED
 for dimensions in [Vector2i(1024,768),Vector2i(1280,720),Vector2i(1920,1080)]:
  root.content_scale_size=dimensions
  # Keep 1080p logical coverage without the macOS desktop clamping the window.
  root.size=Vector2i(1280,720) if dimensions.x==1920 else dimensions
  await frames()
  check(not rect(ui.home.get_node("play_box")).intersects(rect(ui.home.get_node("sidebar"))), "%s: home actions clear the character sidebar" % dimensions)
  ui.open_class_picker()
  await frames()
  for cls in ["knight","demon","warlock"]:
   ui.class_stage.snap_to(cls)
   ui._class_sel=cls
   ui._show_class(cls)
   await frames(3)
   check(inside(ui.class_info) and inside(ui.class_info.find_child("cplay",true,false)), "%s %s: creation frame and Play stay on screen" % [dimensions,cls])
  check(not ui.home.visible,"creation hides home buttons")
  await shot("class-%d" % dimensions.x)
  ui.show_title()
  # Battlegrounds is a lobby type now: its way in is the lobby browser (the old raid page is unused)
  ui.open_battlegrounds()
  await frames()
  check(g.lobby_client.panel.visible and inside(g.lobby_client.panel),"%s: Battlegrounds opens the lobby browser on screen" % dimensions)
  check(not ui.title_idle(),"lobby browser is not idle home screen")
  await shot("bg-%d" % dimensions.x)
  g.lobby_client.panel.hide()
  ui.open_join()
  for i in 12:g.net.found["127.0.0.%d" % (i+1)]={"name":"Adventurer %d"%i,"zone":"Town","t":g.net._clock}
  ui._refresh_join()
  await frames()
  check(ui.join_panel.scale.x >= 0.8,"LAN controls retain readable scale")
  check(inside(ui.join_panel),"%s: long LAN list stays in its window" % dimensions)
  check(not ui.home.visible,"LAN menu hides home buttons")
  await shot("join-%d" % dimensions.x)
  ui.join_panel.find_child("join_back",true,false).pressed.emit()
  await frames()
  check(ui.home.visible and not g.net.listening,"Back restores home and stops discovery")
 if "--layout-only" in OS.get_cmdline_user_args():
  g.net.shutdown()
  g.queue_free()
  await frames(20)
  print("[FLOW] done ",fails," failures")
  quit(1 if fails else 0)
  return
 # Two saves: the older selected character must join, not the newest save.
 for entry in [["flow-a","First Hero","knight"],["flow-b","Second Hero","demon"]]:
  g.char_id=entry[0];g.char_name=entry[1]
  g.hero.set_class(entry[2]);g.hero.new_character();g.save_game()
 ui.show_title()
 ui.home.select("flow-a")
 ui.home.lan_join()
 ui.join_ip.text="127.0.0.1:24799"
 ui.join_ip.text_submitted.emit(ui.join_ip.text)
 await frames(2)
 check(g.char_id=="flow-a" and g.hero.cls=="knight","LAN Join uses the selected character")
 g.net.shutdown()
 await g.exit_to_title()
 ui.home.select("flow-a")
 check(ui.home._play.text=="Enter World","Enter World is the one way into your own game")
 root.content_scale_size=Vector2i(1600,900)
 root.size=Vector2i(1280,720)
 ui.home._play.pressed.emit()
 check(await until(func():return g.playing and not g._busy and not ui._title_busy),"Story button enters gameplay")
 check(g.char_id=="flow-a" and not ui.title_panel.visible and not ui.join_panel.visible and ui.hud.visible,"selected hero reaches gameplay with only gameplay controls")
 await frames()
 check(inside(ui.hint_lbl),"gameplay control hint fits the screen")
 await shot("ingame")
 ui.big_message("The Forsaken Wilds")
 ui.open_waypoints()
 await frames()
 check(ui.wp_panel.visible and not ui.title_panel.visible,"waypoint opens directly in gameplay")
 check(not ui.big_lbl.visible and not ui.hint_lbl.visible,"world announcement and controls hint clear waypoint buttons")
 await shot("waypoint")
 ui.close_all()
 await frames(2)
 check(ui.big_lbl.visible and ui.hint_lbl.visible,"closing the waypoint restores HUD text")
 await g.exit_to_title()
 await frames()
 check(ui.home.visible and not ui.hud.visible,"return home restores screen isolation")
 ui._title_choose("new")     # (the button is hidden: MpMode.CREATE_CHARACTER; the class picker still opens)
 check(await until(func():return ui.class_panel.visible and not ui._title_busy),"Create New Character opens the picker")
 ui.name_edit.text="New Adventurer"
 ui.class_info.find_child("cplay",true,false).pressed.emit()
 check(await until(func():return g.playing and not g._busy),"class Play button enters the town")
 check(g.char_name=="New Adventurer" and FileAccess.file_exists(g.char_dir+"flow-a.json") and FileAccess.file_exists(g.char_dir+"flow-b.json"),"new hero preserves existing characters")
 ui.close_all()
 await frames()
 await shot("new-player")
 await create_timer(9).timeout # Let prior join timeout coroutine settle.
 g.net.shutdown()
 g.queue_free()
 await frames(20)
 print("[FLOW] done ",fails," failures")
 quit(1 if fails else 0)
