extends SceneTree
## Screenshots of the multiplayer screen (MpLobbyView) with sample lobbies, no lobby service needed: browse
## (Battlegrounds, Arena), its loading, empty, failure and full states, and a lobby being prepared (class tiles,
## members, ready); at 1920x1080, 1280x720 and 1024x768. `-- outdir` (needs a display). Prints [MPV] lines with the
## checks it can make (no overlaps off screen, the main actions present).
var g
var out := "user://mp_lobby_shots"
var fails := 0

func _initialize():
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out)
	load("res://scripts/build_env.gd").forced = {"env": "local", "cloud": "0", "lobby_url": "http://127.0.0.1:1"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://mp_lobby_shots_chars/"
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[MPV] %s %s" % ["ok  " if ok else "FAIL", what])

func shot(name: String) -> void:
	for i in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join(name + ".png"))
	print("[SHOT] ", out.path_join(name + ".png"))

func _inside(c: Control) -> bool:
	var r := c.get_global_rect()
	var vp := Rect2(Vector2.ZERO, get_root().get_visible_rect().size)
	return vp.grow(1.0).encloses(r)

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.ui.show_title()
	var c = g.lobby_client
	c.set_process(false)
	c.identity = "me"
	c.auth = "Bearer dev"
	var rooms := [
		{"id": "r1", "mode": "battlegrounds", "name": "Archer's Battlegrounds", "owner": "u1", "members": {"u1": {"name": "Archer", "character": "run_archer", "ready": true}}, "capacity": 16, "joined": 5, "state": "waiting", "joinable": true},
		{"id": "r2", "mode": "battlegrounds", "name": "Night raid", "owner": "u2", "members": {"u2": {"name": "Wraith", "character": "run_wraith"}}, "capacity": 16, "joined": 11, "state": "playing", "joinable": true},
		{"id": "r3", "mode": "battlegrounds", "name": "Full house", "owner": "u3", "members": {"u3": {"name": "Demon"}}, "capacity": 16, "joined": 16, "state": "playing", "joinable": true},
		{"id": "r4", "mode": "arena", "name": "Plague Doctor's Arena", "owner": "u4", "members": {"u4": {"name": "Plague Doctor", "team": 0}}, "capacity": 4, "joined": 1, "team_size": 2, "state": "waiting", "joinable": true},
	]
	for size in [Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(1024, 768)]:
		get_root().size = size
		await process_frame
		var tag := "%d" % size.x
		c.rooms = []
		c.loaded = false
		c.last_error = ""
		c.room = {}
		c.open("battlegrounds")
		c.set_process(false)
		await shot("loading_" + tag)
		c.loaded = true
		c.rooms = rooms
		c.draw()
		await shot("browse_bg_" + tag)
		var create: Control = c.view.find_child("create", true, false)
		check(create != null and create.is_visible_in_tree() and _inside(create), "%s: Create Lobby on screen" % tag)
		check(c.view.find_child("tab_arena", true, false) != null, "%s: the mode tabs" % tag)
		c.view.joinable_only = true
		c.draw()
		await shot("browse_bg_joinable_" + tag)
		c.view.joinable_only = false
		c.selected_mode = "arena"
		c.draw()
		await shot("browse_arena_" + tag)
		c.rooms = []
		c.draw()
		await shot("empty_arena_" + tag)
		c.last_error = "Lobby service unavailable."
		c.selected_mode = "battlegrounds"
		c.draw()
		await shot("error_" + tag)
		c.last_error = ""
		# a lobby being prepared
		c.room = {"id": "r1", "mode": "battlegrounds", "name": "Archer's Battlegrounds", "owner": "me", "capacity": 16, "state": "waiting",
			"members": {"me": {"name": "Plague Doctor", "character": "run_plague", "ready": false, "team": 0},
				"u1": {"name": "Archer", "character": "run_archer", "ready": true, "team": 0},
				"u5": {"name": "Wraith", "character": "run_wraith", "ready": false, "team": 0}}}
		c.run_class = "plague"
		c.draw()
		await shot("prep_bg_" + tag)
		var ready: Control = c.view.find_child("ready", true, false)
		var tiles: Control = c.view.find_child("class_tiles", true, false)
		check(ready != null and _inside(ready), "%s: Ready on screen" % tag)
		check(tiles != null and _inside(tiles) and tiles.get_child_count() >= 8, "%s: the class tiles on screen (%d)" % [tag, tiles.get_child_count() if tiles else 0])
		check(g.ui.title_stage.hero != null and g.ui.title_stage.hero.cls == "plague", "%s: the chosen class stands on the stage" % tag)
		c.run_class = "archer"
		c.room["members"]["me"]["character"] = "run_archer"
		c.draw()
		await shot("prep_bg_archer_" + tag)
		c.room = {}
		c.view.hide()
	print("[MPV] done, %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
