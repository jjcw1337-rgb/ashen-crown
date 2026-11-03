extends SceneTree
## The raid server's checks on player-on-player messages (the Codex audit of 2026-11-02): blows, crowd control and
## burns from a player who is dead, out of range or not in a raid are dropped (Battlegrounds.pvp_pair), the same crowd
## control from one player on another is let through at most every PVP_EFFECT_GAP s, a burn counts for its kill, and
## a monster doesn't pick a hero under a Shadow Phial while it can see another (Game.target_for).
## In one process: the server's side is called directly with two heroes standing in for players (the blows themselves
## go out by RPC, so the test reads what the server recorded: last_hit, pvp_effect_t).
var g
var fails := 0
func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()
func check(ok: bool, what: String) -> void:
	print("[P] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1
func wait(n: int) -> void:
	for i in n:
		await process_frame
func _hero(cls: String, at: Vector3):
	var h = load("res://scripts/hero.gd").new()
	g.add_child(h)
	h.setup(g)
	h.set_class(cls)
	h.new_character()
	h.global_position = at
	return h
func _run() -> void:
	while g.world == null or g._busy:
		await wait(5)
	await g.start_game(false, "knight")
	while g._busy:
		await wait(5)
	g.ui.close_all()
	var a = _hero("archer", Vector3(0, 0, 0))
	var t = _hero("knight", Vector3(5, 0, 0))
	var bg = load("res://scripts/battlegrounds.gd").new()
	bg.game = g
	g.add_child(bg)
	g.net.players = {2: {"name": "A", "hero": a}, 3: {"name": "T", "hero": t}}
	bg.state = "raid"
	bg.raid_t = 10.0
	check(not bg.pvp_pair(2, 3).is_empty(), "two living players 5 m apart in a raid: a blow goes through")
	check(bg.pvp_pair(2, 2).is_empty() and bg.pvp_pair(2, 9).is_empty(), "nobody hits themselves or someone not here")
	bg.state = "reset"
	check(bg.pvp_pair(2, 3).is_empty(), "nothing between rounds")
	bg.state = "raid"
	t.global_position = Vector3(bg.PVP_RANGE + 5.0, 0, 0)
	check(bg.pvp_pair(2, 3).is_empty(), "nothing from across the crypt (%.0f m)" % (bg.PVP_RANGE + 5.0))
	t.global_position = Vector3(5, 0, 0)
	a.dead = true
	bg.pvp_effect(2, 3, "quake", Vector3.ZERO)
	bg.pvp_burn(2, 3, 30.0, Vector3.ZERO)
	check(bg.pvp_effect_t.is_empty() and not bg.last_hit.has(3), "a dead player's stun and burn are dropped")
	a.dead = false
	bg.pvp_effect(2, 3, "quake", Vector3.ZERO)
	check(bg.pvp_effect_t.has("2:3:quake") and bg.last_hit.get(3, [0])[0] == 2, "a living one's stun lands and counts for him")
	bg.raid_t = 10.3
	bg.pvp_effect(2, 3, "quake", Vector3.ZERO)
	check(float(bg.pvp_effect_t["2:3:quake"]) == 10.0, "the same stun again 0.3 s later is dropped (a stream can't chain it)")
	bg.pvp_effect(2, 3, "chill", Vector3.ZERO)
	check(bg.pvp_effect_t.has("2:3:chill"), "another kind isn't held back by it")
	bg.raid_t = 10.0 + bg.PVP_EFFECT_GAP + 0.05
	bg.pvp_effect(2, 3, "quake", Vector3.ZERO)
	check(float(bg.pvp_effect_t["2:3:quake"]) > 10.0, "and after %.1f s it lands again" % bg.PVP_EFFECT_GAP)
	bg.last_hit.clear()
	bg.pvp_burn(2, 3, 30.0, Vector3.ZERO)
	check(bg.last_hit.get(3, [0])[0] == 2, "a burn counts for the kill")
	# the Shadow Phial on the server: the drinker's unseen bit (net_invis) on his stand-in
	var e := Node3D.new()           # (target_for only needs where the monster stands)
	g.add_child(e)
	e.global_position = Vector3(200, 0, 200)
	var hp: Vector3 = g.hero.global_position
	g.hero.global_position = Vector3(-400, 0, -400)
	a.global_position = e.global_position + Vector3(1, 0, 0)
	t.global_position = e.global_position + Vector3(6, 0, 0)
	g.net.active = true
	var saw_a: bool = g.target_for(e) == a
	a.net_invis = true
	var pick = g.target_for(e)
	check(saw_a and pick == t, "a monster leaves the unseen one for a hero it can see (%s)" % (pick.name if pick != null else "none"))
	g.net.active = false
	g.net.players = {}
	g.hero.global_position = hp
	print("[P] done, %d failed" % fails)
	quit()
