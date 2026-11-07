extends SceneTree
## Run with the real renderer: --path . -s game/maps/camp/tests/waypoint_activities_test.gd -- /tmp/waypoint-menu
## Runtime loads avoid compiling autoload users before the autoloads exist.
var g
var data
var fails := 0
func ok(cond: bool, label: String) -> void:
 print("[ACTIVITY] ", "ok " if cond else "FAIL ", label)
 if not cond: fails += 1
func _initialize():
 g = load("res://main.tscn").instantiate()
 get_root().add_child(g)
 _run()
func settle():
 for i in 6: await process_frame
 while g._busy: await process_frame
 # Aurelia builds its crowd atlas asynchronously after load_zone finishes. Let that
 # rendering job settle before the harness immediately unloads its entire world.
 if g.world.has_meta("games") and DisplayServer.get_name() != "headless":
  var games_script = load("res://scripts/games.gd")
  var deadline := Time.get_ticks_msec() + 30000
  while games_script._atlas == null and Time.get_ticks_msec() < deadline:
   await process_frame
  ok(games_script._atlas != null, "Aurelia crowd rendering finishes before departure")
func shot(label: String):
 g.ui.msg_lbl.visible = false
 g.ui.big_lbl.visible = false
 for i in 20: await process_frame
 if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().size() > 0:
  await RenderingServer.frame_post_draw
  get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "-" + label + ".png")
func _run():
 while g.world == null or g._busy or g._intro_playing:
  g._intro_skip = true
  await process_frame
 data = load("res://scripts/data.gd")
 await g.start_game(false, "knight")
 g.ui.close_all()
 g.hero.global_position = g.world.spawns["waypoint_town"]
 g.max_run = 0
 g.hero.level = 1
 g.waypoints_known = ["town"]
 var retired: int = 0 if MpMode.WAVES else data.WAYPOINT_ACTIVITIES.filter(func(e): return str(e.get("id", "")) == "vigil").size()
 ok(g.waypoint_activities().size() == data.WAYPOINT_ACTIVITIES.size() - retired + load("res://scripts/isles.gd").ISLANDS.size() + data.WAYPOINT_ACTS.size(), "all live activities, islands and act dungeons listed (Endless Waves retired: MpMode)")
 ok(g.waypoint_activity_lock(g.waypoint_activity("isle_verdant")) != "", "island level gate retained")
 ok(g.waypoint_activity_lock(g.waypoint_activity("lair_0")) != "", "dungeon discovery gate retained")
 ok(g.waypoint_activity_lock(g.waypoint_activity("lair_1")) != "", "sealed act cannot be entered")
 g.waypoint_activity_go("missing")
 ok(g.cur_zone == "town" and not g._busy, "unknown destination rejected")
 var panel = g.ui.wp_panel
 panel.open()
 panel.sel_group = "pve"
 panel._fill()
 await settle()
 ok(panel.route_box.get_child_count() == g.waypoint_activities().size(), "one styled button per PvE activity")
 await shot("pve")
 var daily := {"id": "test_daily", "name": "Daily Vigil", "group": "daily", "route": "zone", "run": 0, "zone": "vigil", "spawn": "start", "description": "A scheduled journey to the Last Flame."}
 data.WAYPOINT_ACTIVITIES.append(daily)
 await create_timer(1.1).timeout
 panel.sel_group = "daily"
 panel._fill()
 await settle()
 ok(panel.route_box.get_child_count() == 1, "new daily appears without UI changes")
 await shot("daily")
 daily["ends_at"] = Time.get_unix_time_from_system() - 1
 await create_timer(1.1).timeout
 ok(g.waypoint_activity("test_daily").is_empty() and panel.sel_group != "daily", "expired daily and empty category disappear while open")
 g.waypoint_activity_go("test_daily")
 ok(g.cur_zone == "town" and not g._busy, "stale daily click rejected")
 data.WAYPOINT_ACTIVITIES.erase(daily)
 var bad := daily.duplicate()
 bad.erase("ends_at")
 bad["zone"] = "unimplemented"
 data.WAYPOINT_ACTIVITIES.append(bad)
 ok(g.waypoint_activity("test_daily").is_empty(), "unimplemented route is not offered")
 data.WAYPOINT_ACTIVITIES.erase(bad)
 panel.sel_group = "battlegrounds"
 panel._fill()
 await settle()
 await shot("pvp")
 g.ui.close_all()
 g.waypoint_battleground("crypt")
 ok(g.lobby_client.panel.visible and not g.bg_mode, "the Battlegrounds card opens the lobbies without connecting")
 g.lobby_client.panel.hide()
 g.hero.level = 20
 g.max_run = 2
 g.waypoints_known = ["town", "wild"]
 g.run_progress = {"1": {"waypoints": ["town", "wild"]}, "2": {"waypoints": ["town", "wild"]}}
 panel.close()
 # Exercise real button signals and online handoff against a transport spy.
 var spy = load("res://game/maps/camp/tools/waypoint_route_spy.gd").new()
 spy.ui = g.ui
 spy.hero = g.hero
 spy.net = g.net
 spy.world = g.world
 spy.playing = true
 spy.char_id = "waypoint-test"
 spy.char_name = "Waypoint Test"
 spy.max_run = 2
 spy.waypoints_known = ["town", "wild"]
 spy.run_progress = g.run_progress.duplicate(true)
 get_root().add_child(spy)
 spy.set_process(false)
 panel.game = spy
 for entry in spy.waypoint_activities():
  var card = panel._activity_card(entry)
  panel.route_box.add_child(card)
  var buttons: Array = card.find_children("*", "Button", true, false)
  spy.dispatched.clear()
  buttons[0].pressed.emit()
  var expected := ["travel", 0, entry["zone"], entry["spawn"]] if int(entry["run"]) == 0 else ["switch", int(entry["run"]), entry["zone"], entry["spawn"]]
  ok(spy.dispatched.has(expected), "button dispatches correct destination " + str(entry["id"]))
  card.queue_free()
 daily.erase("ends_at")
 data.WAYPOINT_ACTIVITIES.append(daily)
 spy.dispatched.clear()
 spy.waypoint_activity_go("test_daily")
 ok(spy.dispatched == [["travel", 0, "vigil", "start"]], "active daily routes to its registered destination")
 daily["enabled"] = false
 ok(spy.waypoint_activity("test_daily").is_empty(), "disabled daily withdrawn")
 data.WAYPOINT_ACTIVITIES.erase(daily)
 panel.game = g
 spy.queue_free()
 # Every enabled zone route reaches an actual world and a clear, named spawn.
 var entries: Array = [] if OS.get_cmdline_user_args().has("--catalog-only") else g.waypoint_activities()
 for entry in entries:
  g.waypoint_activity_go(str(entry["id"]))
  await settle()
  ok(g.cur_zone == str(entry["zone"]) and g.difficulty == int(entry["run"]), "travels to " + str(entry["name"]))
  ok(g.world.spawns.has(str(entry["spawn"])), "registered arrival exists for " + str(entry["id"]))
  ok(not g.world.solid_at(g.hero.position.x, g.hero.position.z), "arrival is clear for " + str(entry["id"]))
 print("[ACTIVITY] done, ", fails, " failures")
 g.queue_free()
 for i in 12: await process_frame
 quit(1 if fails else 0)
