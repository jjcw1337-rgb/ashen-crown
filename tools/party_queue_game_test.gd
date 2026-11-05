extends SceneTree
## Three real game processes. Server: -- --server --coop --port 24770 --queue-port 24769 server
## Clients: -- a / -- b. Uses isolated test characters, real background queue + game sockets.
var g
var role := "a"
var fails := 0
func _initialize():
 node_added.connect(func(n):
  if n is SubViewport:n.disable_3d = true) # Skip unrelated title/portrait drawing in network tests.
 var args := OS.get_cmdline_user_args()
 role = "server" if args.has("server") else ("b" if args.has("b") else "a")
 var env = load("res://scripts/build_env.gd")
 env.forced = {"env":"staging", "cloud":"0", "party_queue":"127.0.0.1:24769", "coop_server":"127.0.0.1:24770"}
 g = load("res://main.tscn").instantiate()
 g.char_dir = "user://queue_test_" + role + "/"
 root.disable_3d = true
 root.add_child(g)
 run()
func check(ok: bool, what: String):
 print("[PARTY-",role,"] ","ok " if ok else "FAIL ",what)
 if not ok:fails += 1
func until(condition: Callable, seconds := 90.0) -> bool:
 var end := Time.get_ticks_msec() + int(seconds * 1000)
 while Time.get_ticks_msec() < end:
  g._intro_skip = true
  if condition.call(): return true
  await process_frame
 return false
func wait_s(t: float):
 await create_timer(t).timeout
func shot(name: String):
 if DisplayServer.get_name() == "headless":return
 root.disable_3d = false
 for i in 3:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("/tmp/party-" + name + ".png")
 root.disable_3d = true
func run():
 Engine.max_fps = 30
 if role == "server":
  check(await until(func(): return g.coop_server != null and g.coop_server.party_queue != null and not g._busy), "co-op world and queue ready")
  check(await until(func(): return g.net.players.size() == 2, 240.0), "both queued players admitted to the real co-op world")
  check(await until(func(): return g.net.players.is_empty(), 180.0), "clients finish and disconnect cleanly")
 else:
  check(await until(func(): return g.world != null and not g._busy and not g._intro_playing), "solo world loaded")
  await g.start_game(false, "knight", "", "Queue " + role)
  g.ui.close_all()
  g.hero.gold = 1234
  g.max_run = 0
  g.save_game()
  var character: String = g.char_id
  if role == "b":
   g.party_join_ticket = "invalid-reservation"
   g.party_join_pending = true
   g.start_join("127.0.0.1:24770", character)
   check(await until(func(): return not g.party_join_pending and not g.net.active, 15), "invalid reservation rejected over game socket")
   check(g.playing and not g.ui.title_panel.visible and g.party_join_ticket == "", "failed handoff keeps solo adventure open and clears ticket")
   await wait_s(7)
  g.waypoint_activity_go("find_party")
  check(await until(func(): return g.party_queue.state in ["queued", "ready"], 15), "background search connects")
  if role == "a":
   var origin: Vector3 = g.hero.global_position
   g.hero.cmd_move(origin + Vector3(3,0,0))
   await wait_s(2)
   check(g.hero.global_position.distance_to(origin) > 1, "hero moves while queued")
   await shot("searching")
  check(await until(func(): return g.party_queue.state == "ready", 90), "party found popup")
  check(not g.net.active and g.playing, "ready popup leaves solo adventure running")
  if role == "a":await shot("ready")
  g.party_queue.accept.pressed.emit()
  check(await until(func(): return g.net.is_client() and g.net.welcomed and not g.net.loading and not g._busy, 60), "accepted queue hands off to co-op")
  check(g.char_id == character and g.hero.gold == 1234, "current character and progress preserved")
  check(await until(func(): return g.net.players.size() == 1, 30), "partner visible in party roster")
  check(g.party_queue.state == "idle" and not g.party_queue.panel.visible, "queue closes after handoff")
  if role == "a":await shot("joined")
  await wait_s(10) # Let the existing join timeout coroutine finish before teardown.
 g.net.shutdown()
 if role == "a":
  load("res://scripts/build_env.gd").forced["party_queue"] = "127.0.0.1:24789"
  g.party_queue.begin()
  check(await until(func(): return g.party_queue.state == "idle", 18), "unreachable queue times out")
  check(g.playing and not g.net.active and not g.ui.title_panel.visible, "queue failure leaves solo play available")
 g.queue_free()
 for i in 20:await process_frame
 print("[PARTY-",role,"] done ",fails," failures")
 quit(1 if fails else 0)
