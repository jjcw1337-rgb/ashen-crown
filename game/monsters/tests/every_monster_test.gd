extends SceneTree
## Every monster with a card (Monsters.kinds), one at a time in the Sandbox: it spawns on its own body (posed, the
## rig its card gives), notices the hero and fights for a few seconds (its brain and moves, the hero immortal), then
## is struck down and goes through its death. A card that breaks any of that shows here, by name. Also checks the
## registry: every Data.ENEMIES kind is on exactly one card, and every card's kinds are real.
##   godot --path . --fixed-fps 60 -s tools/_late.gd -- res://game/monsters/tests/every_monster_test.gd
var g
var fails := 0
const FIGHT_FRAMES := 180      # 3 s of fighting each

func _initialize():
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://every_monster_test/"
	g.old_save = "user://every_monster_test/absent.json"
	get_root().add_child(g)
	current_scene = g
	_run()

func _process(_dt: float) -> bool:
	if is_instance_valid(g):
		g._intro_skip = true
	return false

func check(ok: bool, what: String) -> void:
	print("[EVERY] ", "ok   " if ok else "FAIL ", what)
	if not ok:
		fails += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	# the registry
	var carded: Array = Monsters.kinds()
	var missing: Array = Data.ENEMIES.keys().filter(func(k) -> bool: return not k in carded)
	var unknown: Array = carded.filter(func(k) -> bool: return not Data.ENEMIES.has(k))
	check(missing.is_empty(), "every Data.ENEMIES kind is on a card (missing: %s)" % str(missing))
	check(unknown.is_empty(), "every card's kinds are in Data.ENEMIES (unknown: %s)" % str(unknown))
	while g.world == null or g._busy:
		await frames(5)
	await g.start_game(false, "knight")
	while g._busy:
		await frames(5)
	g.ui.close_all()
	await g.open_sandbox()
	while g._busy:
		await frames(5)
	var sb = g.sandbox
	check(sb != null, "the sandbox opens")
	if sb == null:
		_end()
		return
	var h = g.hero
	g.test_immortal = true
	var kinds: Array = sb.any_monsters()
	check(kinds.size() == carded.size(), "the Sandbox offers every monster (%d)" % kinds.size())
	for k in kinds:
		sb.clear_monsters()
		await frames(2)
		h.global_position = Vector3(0, 0, 0)
		var e: Enemy = g.spawn_enemy(k, Vector3(0, 0, -6), maxi(1, h.level), false)
		if e == null:
			check(false, "%s spawns" % k)
			continue
		e.aggro = true
		var built: bool = e.rig != null and e.rig.get_meta("kind", "") == k
		var y0: Vector3 = e.global_position
		var moved := 0.0
		var posed := false
		var rest: Transform3D = _first_mesh_xf(e.rig)
		for i in FIGHT_FRAMES:
			await process_frame
			if not is_instance_valid(e):
				break
			moved = maxf(moved, (e.global_position - y0).length())
			if not posed and _first_mesh_xf(e.rig) != rest:
				posed = true
		if not is_instance_valid(e):
			check(false, "%s survives its own fight" % k)
			continue
		e.take_damage(e.life + 99999.0, 0.0, h.global_position, 0.0, false)
		for i in 60:
			await process_frame
		check(built and posed and e.dead, "%s (%s): its body from its card, %s, moved %.1f m, killed: %s" % [
			k, str(Data.ENEMIES[k].get("name", k)), "animated" if posed else "still", moved, str(e.dead)])
	sb.clear_monsters()
	_end()

## Any of the body's pieces' place under the rig (the pose moves at least one bone or part of every body).
func _first_mesh_xf(r: Node3D) -> Transform3D:
	var acc := Transform3D()
	for n in r.find_children("*", "Node3D", true, false):
		acc = acc * (n as Node3D).transform
	var sk := r.find_children("*", "Skeleton3D", true, false)
	for s in sk:
		for b in mini((s as Skeleton3D).get_bone_count(), 40):
			acc = acc * (s as Skeleton3D).get_bone_pose(b)
	return acc

func _end() -> void:
	print("[EVERY] done, %d failed" % fails)
	quit(1 if fails else 0)
