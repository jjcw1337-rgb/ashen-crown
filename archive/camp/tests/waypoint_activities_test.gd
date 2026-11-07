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
 data = load("res://game/systems/data/data.gd")
 await g.start_game(false, "knight")
 g.ui.close_all()
 g.hero.global_position = g.world.spawns["waypoint_town"]
 g.hero.level = 1
 g.waypoints_known = ["town"]
 ok(g.waypoint_activities().size() == data.WAYPOINT_ACTIVITIES.size(), "all live activities listed")
 var gated := {"id": "test_gated", "name": "Gated Camp", "group": "pve", "route": "zone", "run": 0, "zone": "town", "spawn": "start", "level": 99}
 data.WAYPOINT_ACTIVITIES.append(gated)
 ok(g.waypoint_activity_lock(g.waypoint_activity("test_gated")) != "", "level gate retained")
 data.WAYPOINT_ACTIVITIES.erase(gated)
 var hidden := {"id": "test_hidden", "name": "Hidden Camp", "group": "pve", "route": "zone", "run": 0, "zone": "town", "spawn": "start", "requires_waypoint": "nowhere"}
 data.WAYPOINT_ACTIVITIES.append(hidden)
 ok(g.waypoint_activity_lock(g.waypoint_activity("test_hidden")) != "", "waypoint discovery gate retained")
 data.WAYPOINT_ACTIVITIES.erase(hidden)
 var other_act := {"id": "test_act2", "name": "Act II", "group": "pve", "route": "zone", "run": 1, "zone": "town", "spawn": "start"}
 data.WAYPOINT_ACTIVITIES.append(other_act)
 ok(g.waypoint_activity("test_act2").is_empty(), "an activity in another act is not offered (Act I is the only act)")
 data.WAYPOINT_ACTIVITIES.erase(other_act)
 g.waypoint_activity_go("missing")
 ok(g.cur_zone == "town" and not g._busy, "unknown destination rejected")
 var panel = g.ui.wp_panel
 var pve := {"id": "test_pve", "name": "Camp Errand", "group": "pve", "route": "zone", "run": 0, "zone": "town", "spawn": "start", "description": "A walk round the camp."}
 data.WAYPOINT_ACTIVITIES.append(pve)
 panel.open()
 panel.sel_group = "pve"
 panel._fill()
 await settle()
 ok(g.waypoint_activities().size() >= 1 and panel.route_box.get_child_count() == g.waypoint_activities().size(), "one styled button per PvE activity")
 await shot("pve")
 data.WAYPOINT_ACTIVITIES.erase(pve)
 var daily := {"id": "test_daily", "name": "Daily Round", "group": "daily", "route": "zone", "run": 0, "zone": "town", "spawn": "start", "description": "A scheduled walk round the camp."}
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
 spy.waypoints_known = ["town"]
 get_root().add_child(spy)
 spy.set_process(false)
 panel.game = spy
 for entry in spy.waypoint_activities():
  var card = panel._activity_card(entry)
  panel.route_box.add_child(card)
  var buttons: Array = card.find_children("*", "Button", true, false)
  spy.dispatched.clear()
  buttons[0].pressed.emit()
  var expected := ["travel", 0, entry["zone"], entry["spawn"]]
  ok(spy.dispatched.has(expected), "button dispatches correct destination " + str(entry["id"]))
  card.queue_free()
 daily.erase("ends_at")
 data.WAYPOINT_ACTIVITIES.append(daily)
 spy.dispatched.clear()
 spy.waypoint_activity_go("test_daily")
 ok(spy.dispatched == [["travel", 0, "town", "start"]], "active daily routes to its registered destination")
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
