extends SceneTree
var g
var fails := 0
func _initialize():
 load("res://scripts/build_env.gd").forced = {"env":"staging","cloud":"0"}
 g=load("res://main.tscn").instantiate()
 g.char_dir="user://title_layout_test/"
 root.add_child(g)
 run()
func check(ok: bool, label: String):
 print("[TITLE] ","ok " if ok else "FAIL ",label)
 if not ok:fails+=1
func settle():
 for i in 12:await process_frame
func run():
 while g.ui == null or g._intro_playing or g._busy:
  g._intro_skip=true
  await process_frame
 await settle()
 root.mode=Window.MODE_WINDOWED
 for dimensions in [Vector2i(1920,1080),Vector2i(1280,720),Vector2i(1024,768)]:
  root.content_scale_size=dimensions
  root.size=dimensions
  await settle()
  var h=g.ui.home
  var bg:Rect2=h.get_node("bg_card").get_global_rect()
  var side:Rect2=h.get_node("sidebar").get_global_rect()
  var head:Rect2=h.get_node("title_head").get_global_rect()
  check(head.end.x <= side.position.x and head.position.x >= bg.end.x, "%s: title stays between columns" % dimensions)
  for mode in ["story","online","lan"]:
   h.set_mode(mode)
   await settle()
   var play:Rect2=h.get_node("play_box").get_global_rect()
   check(not bg.intersects(play) and not side.intersects(play), "%s %s: play controls clear of Battlegrounds and character sidebar" % [dimensions,mode])
  if DisplayServer.get_name() != "headless":
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("/tmp/title-layout-%d.png" % dimensions.x)
 g.ui.chars_panel.show()
 await settle()
 check(not g.ui.home.visible,"home/Battlegrounds hidden behind character selection")
 g.ui.chars_panel.hide()
 g.ui.class_panel.show()
 await settle()
 check(not g.ui.home.visible,"home/Battlegrounds hidden behind character creation")
 g.ui.class_panel.hide()
 await settle()
 check(g.ui.home.visible,"home controls return after closing character screen")
 g.queue_free()
 await settle()
 print("[TITLE] done ",fails," failures")
 quit(1 if fails else 0)
