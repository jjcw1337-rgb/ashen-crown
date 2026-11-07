extends SceneTree
## A player that stays and plays, for measuring what a server costs per player (Blaine, 2026-11-05: "is running
## each map the main cost, with extra players adding relatively little?"). Joins a co-op server (`coop`) or a
## Battlegrounds server (`bg`), then for `secs` walks about and fights whatever is near. The `lead` co-op bot takes the
## party to the Verdant Reach (the others say yes to the ready check). Headless:
##   godot --headless --path . -s tools/load_bot.gd -- coop|bg <port> <secs> [lead] [addr <host>] [n <index>]
## Prints "[BOT] ..." lines.

var g
var mode := "coop"
var port := 24641
var host := "127.0.0.1"
var secs_left := 60.0
var lead := false
var idx := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	mode = "bg" if a.has("bg") else "coop"
	var nums: Array = Array(a).filter(func(x): return str(x).is_valid_float())
	if nums.size() > 0:
		port = int(nums[0])
	if nums.size() > 1:
		secs_left = float(nums[1])
	lead = a.has("lead")
	if a.find("addr") >= 0:
		host = a[a.find("addr") + 1]
	if a.find("n") >= 0:
		idx = int(a[a.find("n") + 1])
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	process_frame.connect(_answer_votes)
	_run()

func _answer_votes() -> void:
	if not lead and g != null and g.ui != null and g.ui.vote_panel != null and g.ui.vote_panel.visible and g.ui.vote_yes.visible:
		g.ui.vote_yes.pressed.emit()

func until(f: Callable, t: float) -> bool:
	var end := Time.get_ticks_msec() + int(t * 1000.0)
	while Time.get_ticks_msec() < end:
		if f.call():
			return true
		await process_frame
	return false

func _run() -> void:
	Engine.max_fps = 30
	while g.world == null or g._busy:
		await process_frame
	await create_timer(0.5 + idx * 1.5).timeout
	g.test_immortal = true
	var cls: String = ["knight", "archer", "demon", "plague", "wraith", "warlock"][idx % 6]
	if mode == "bg":
		g.char_dir = "user://bot_chars_%d/" % idx
		DirAccess.make_dir_recursive_absolute(g.char_dir)
		g.hero.set_class(cls)
		g.hero.new_character()
		g.char_id = g.new_char_id()
		g.char_name = "Bot%d" % idx
		g.save_game()
		await g.start_battlegrounds("%s:%d" % [host, port], g.char_id)
	else:
		g.char_dir = "user://bot_chars_%d/" % idx
		await g.start_join("%s:%d" % [host, port])
	var ok := await until(func(): return g.net.is_client() and not g._busy and not g.net.loading and g.world != null, 60.0)
	print("[BOT] %d joined %s: %s (zone %s)" % [idx, mode, ok, g.cur_zone])
	if mode == "coop" and lead:
		await create_timer(8.0).timeout
		g.travel(0, "bg", "start")
		await until(func(): return g.cur_zone == "bg" and not g._busy and not g.net.loading, 60.0)
	var end := Time.get_ticks_msec() + int(secs_left * 1000.0)
	var hits := 0
	while Time.get_ticks_msec() < end:
		await create_timer(0.6).timeout
		if g.hero == null or g._busy or g.world == null:
			continue
		var best: Node3D = null
		var bd := 14.0
		for e in g.world.enemies_root.get_children():
			if e is Node3D and is_instance_valid(e):
				var d: float = (e as Node3D).global_position.distance_to(g.hero.global_position)
				if d < bd:
					bd = d
					best = e
		if best != null:
			g.hero.swipe_attack(best.global_position)
			hits += 1
		else:
			var p: Vector3 = g.hero.global_position + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8))
			g.hero._set_goal(p, false)
	print("[BOT] %d done in %s: %d attacks" % [idx, g.cur_zone, hits])
	quit()
