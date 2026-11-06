extends SceneTree
## A connection that closes while a zone loads (triage 2026-11-03, issue b43c39456b33870a: a raid join turned away
## mid-load sent `sv_zone_ready` to the offline peer: "RPC 'sv_zone_ready' on yourself is not allowed").
##   godot --headless --path . -s tools/nightly_net_drop_test.gd      (in the nightly gate)
## The client's trip (`Net._client_goto`) is started, the link is shut down while the zone loads, and the trip must
## finish quietly: no RPC afterwards (this session's log, user://logs/godot.log, must not hold the error), the game
## offline and idle.

var g
var fails := 0

func _initialize():
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://gate/net_drop/"
	g.old_save = g.char_dir + "absent.json"
	get_root().add_child(g)
	current_scene = g
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("[D] ok   " if ok else "[D] FAIL ") + what)

func wait(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	Engine.max_fps = 60
	await wait(30)
	while g._busy:
		await wait(5)
	g.start_game(false)
	await wait(10)
	while g._busy:
		await wait(5)
	# a client link (nobody listens on this port: it stays "connecting", like a raid server about to refuse)
	check(g.net.join("127.0.0.1", 24697) == OK, "joined a link")
	var link: ENetMultiplayerPeer = g.net.peer
	check(not g.net.still_joined(link), "a link that never connected doesn't count as joined")
	g.net._client_goto(0, "wild", "start", null)
	var t := 0
	while not g._busy and t < 120:
		await wait(1)
		t += 1
	check(g._busy, "the trip's zone is loading")
	g.net.shutdown()          # the server turns the join away (Net._on_server_gone shuts the link down)
	check(not g.net.still_joined(link), "a link shut down doesn't count as joined")
	t = 0
	while g._busy and t < 1200:
		await wait(5)
		t += 5
	await wait(30)
	check(not g._busy and g.cur_zone == "wild", "the zone finished loading")
	check(not g.net.active and not g.net.loading, "offline and not waiting on a host")
	var stale := Enemy.new()
	stale.net_id = 23
	g.net.send_enemy_hit(stale, 10.0, 0.0, Vector3.ZERO, 0.0, false)
	g.net.send_enemy_chill(stale, 0.2, 2.0)
	g.net.send_enemy_stun(stale, 1.0)
	stale.free()
	await wait(2)
	var txt := FileAccess.get_file_as_string("user://logs/godot.log")
	check(txt != "" and not txt.contains("on yourself is not allowed"), "no RPC sent to the closed link")
	print("[D] done, %d failed" % fails)
	g.queue_free()
	await wait(20)
	quit(1 if fails else 0)
