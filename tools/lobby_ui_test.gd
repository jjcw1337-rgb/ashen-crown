extends SceneTree
## Render the actual post-intro home and multiplayer widgets at three logical viewport sizes.
var g
var fails:=0
var checks:=0
func _initialize():
 load("res://scripts/build_env.gd").forced={"env":"local","cloud":"0","lobby_url":"http://127.0.0.1:7352"}
 g=load("res://main.tscn").instantiate();g.char_dir="user://lobby_ui_test/";root.add_child(g);run()
func check(ok: bool,label: String):
 checks+=1;print("[LOBBY-UI] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func wait_s(t: float):await create_timer(t).timeout
func shot(name: String):
 await wait_s(0.7);await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/lobby-ui-"+name+".png")
func run():
 Engine.max_fps=30
 var deadline:=Time.get_ticks_msec()+120000
 while (g.world==null or g._busy or g._intro_playing) and Time.get_ticks_msec()<deadline:
  g._intro_skip=true;await process_frame
 g.char_id="uihero";g.char_name="Arena Hero";g.save_game();g.char_id="";g.ui.show_title();g.ui.home.select("uihero")
 var c=g.lobby_client;c.set_process(false);c.identity="a";c.auth="Bearer dev-ui"
 check(g.ui.home.get_node("play_box/buttons").get_child_count()==3,"exactly three main home choices")
 for size in [Vector2i(1024,768),Vector2i(1280,720),Vector2i(1920,1080)]:
  root.size=Vector2i(1280,720) if size.x>1280 else size
  root.content_scale_size=size;root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
  c.panel.hide()
  await shot("home-"+str(size.x))
  check(g.ui.home._play.visible and g.ui.home._play.text=="Enter World","Enter World "+str(size.x))
  var buttons=g.ui.home.get_node("play_box/buttons").get_children()
  for a in buttons:
   for b in buttons:
    if a!=b:check(not a.get_global_rect().intersects(b.get_global_rect()),"home modes do not overlap")
  g.ui.home._mp.pressed.emit()
  await wait_s(0.5)
  check(c.panel.visible and not g.ui.home.visible,"Multiplayer opens from post-intro home")
  check(c.lan_row.visible,"LAN remains inside Multiplayer (Local network)")
  c.room={};c.rooms=[{"id":"l1","name":"Aldric's Battlegrounds","mode":"battlegrounds","team_size":1,"capacity":16,"state":"waiting","owner":"o1","members":{"o1":{"name":"Aldric"}},"joined":3,"joinable":true},
   {"id":"l2","name":"Mira's Arena","mode":"arena","team_size":2,"capacity":4,"state":"waiting","owner":"o2","members":{"o2":{"name":"Mira"}},"joined":1,"joinable":true,"wager":true},
   {"id":"l3","name":"Doug's Endless Waves","mode":"waves","team_size":1,"capacity":4,"state":"playing","owner":"o3","members":{"o3":{"name":"Doug"}},"joined":4,"joinable":false}]
  c.loaded=true;c.selected_mode="battlegrounds";c.draw();await shot("browser-"+str(size.x))
  # (MpLobbyView: one mode's lobbies at a time, chosen by the tabs; Waves never listed)
  check(c.rows.get_child_count()==1 and c.view.find_child("tab_arena",true,false)!=null and c.view.find_child("tab_waves",true,false)==null,"the list shows this mode's open games, tabs for the others "+str(size.x))
  c.selected_mode="arena";c.draw();await shot("browser-arena-"+str(size.x))
  check(c.rows.get_child_count()==1,"the Arena tab lists the Arena's games "+str(size.x))
  var vis:Rect2=root.get_visible_rect()
  check(vis.grow(1).encloses(c.panel.get_global_rect()) and c.panel.get_global_rect().size.x>=vis.size.x-2,"the screen fills the window, nothing past it "+str(size.x))
  c.rooms=[]
  c.room={"id":"sample","name":"Arena 3v3","mode":"arena","team_size":3,"capacity":6,"state":"waiting","owner":"a","wager":true,"members":{}}
  for i in 6:c.room.members[str(i)]={"name":"Hero "+str(i+1),"team":0 if i<3 else 1,"ready":true,"stake":{"name":"Rare longsword"}}
  c.draw();await shot("stakes-"+str(size.x))
  var on_screen:=true
  for nm in ["leave","ready","start","back","survivors_top"]:
   var b=c.view.find_child(nm,true,false)
   if b==null or not root.get_visible_rect().grow(1).encloses(b.get_global_rect()):on_screen=false;print("[LOBBY-UI] off screen: ",nm)
  check(on_screen,"a full 3v3 lobby keeps every control on screen "+str(size.x))
  c.room={"id":"bgs","name":"Raid","mode":"battlegrounds","capacity":16,"state":"waiting","owner":"a","members":{"a":{"name":"Archer","character":"run_archer"}}}
  c.draw();await shot("prep-bg-"+str(size.x))
  var tiles=c.view.find_child("class_tiles",true,false)
  check(tiles!=null and root.get_visible_rect().grow(1).encloses(tiles.get_global_rect()) and root.get_visible_rect().grow(1).encloses(c.view.find_child("ready",true,false).get_global_rect()),"the class tiles and Ready fit "+str(size.x))
  c.room={};c.panel.hide()
 c.set_process(false);c.panel.hide()
 await g.start_game(true,"knight","uihero")
 g.ui.wp_panel.open()
 await shot("waypoint")
 check(g.ui.wp_panel.visible,"in-game waypoint remains available")
 g.ui.close_all();c.character=g.char_id
 c.play_solo_waves()
 await wait_s(5)
 check(g.cur_zone!="vigil","Endless Waves is retired: its solo start goes nowhere (MpMode.WAVES)")
 await shot("waves-solo")
 await g.exit_to_title()
 await g.start_game(true,"knight","uihero")
 g.hero.gold=8765;g.save_game()
 c.character=g.char_id;c.match_id="failed-admission-test";c.admitted=false
 await g.start_battlegrounds("127.0.0.1:1",c.character)
 for attempt in 25:
  if not g.playing:break
  await wait_s(1)
 check(not g.playing,"unavailable match returns to home")
 var saved=JSON.parse_string(FileAccess.get_file_as_string(g.char_dir+"uihero.json"))
 check(saved.hero.gold==8765 and not saved.in_raid,"failed admission preserves gold and raid eligibility")
 await wait_s(10)
 g.queue_free()
 for i in 30:await process_frame
 print("[LOBBY-UI] done ",checks," checks / ",fails," failures");quit(1 if fails else 0)
