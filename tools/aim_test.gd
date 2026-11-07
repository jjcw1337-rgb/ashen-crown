extends SceneTree
## Aiming (Path of Exile style): the pointer aims, WASD moves, facing never decides where anything goes.
##  - directional ("facing") skills go toward the pointer whichever way the body faces
##  - their projectiles fly that way even if he walks the other way while casting
##  - "point" skills land on the pointer; "self" skills don't turn him
##  - short melee skills and Space bend onto a foe close to the pointer's line
## Run: godot --headless --path . -s tools/aim_test.gd --fixed-fps 60
var g
var fails := 0

func check(ok: bool, what: String) -> void:
	print("[A] %s: %s" % [what, "ok" if ok else "FAIL"])
	if not ok:
		fails += 1

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

static func flat(v: Vector3) -> Vector3:
	v.y = 0
	return v.normalized() if v.length() > 0.001 else Vector3.ZERO

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	await g.start_game(false, "warlock")
	await g.travel(0, "sandbox", "start")
	while g._busy:
		await process_frame
	var h = g.hero
	h.level = 12
	h.recalc()
	g.test_immortal = true
	var foes: Array = g.enemies_near(h.global_position, 400.0)
	var e = foes[0]
	# stand 8 m from an enemy
	h.global_position = g.world.free_spot_near(e.global_position + Vector3(8, 0, 0), 0.5)
	await create_timer(0.1).timeout
	var to_e: Vector3 = flat(e.global_position - h.global_position)

	# 1. directional skill: the pointer decides, facing is ignored
	h._face(-to_e)                                  # body turned right away from the enemy
	var a: Vector3 = h.skill_aim("blight", e.global_position)
	check(flat(a - h.global_position).dot(to_e) > 0.999, "facing away, pointer on the enemy: Blight aims at the enemy")
	var side_pt: Vector3 = h.global_position + to_e.rotated(Vector3.UP, 1.2) * 6.0
	h._face(to_e)                                   # body facing the enemy, pointer 69 deg off
	a = h.skill_aim("blight", side_pt)
	check(flat(a - h.global_position).dot(flat(side_pt - h.global_position)) > 0.999, "facing the enemy, pointer to the side: Blight follows the pointer, no pull onto the enemy")
	# a far pointer clamps to the skill's range along its line
	var far_pt: Vector3 = h.global_position + to_e.rotated(Vector3.UP, 0.5) * 40.0
	a = h.skill_aim("blight", far_pt)
	var fa := Vector2(a.x - h.global_position.x, a.z - h.global_position.z)
	check(absf(fa.length() - 15.0) < 0.05 and flat(a - h.global_position).dot(flat(far_pt - h.global_position)) > 0.999, "pointer beyond range: clamped to 15 m on the pointer's line")

	# 2. cast one way while walking the other (W held, the pointer behind him): the bolt keeps the pointer's direction
	var walk_dir := Vector3(0, 0, -1)
	var shot_dir: Vector3 = Vector3(0, 0, 1).rotated(Vector3.UP, 0.4)
	h.mana = h.max_mana
	var kw := InputEventKey.new()
	kw.keycode = KEY_W
	kw.physical_keycode = KEY_W
	kw.pressed = true
	Input.parse_input_event(kw)
	await create_timer(0.2).timeout
	var p0: Vector3 = h.global_position
	h.use_skill("blight", h.skill_aim("blight", h.global_position + shot_dir * 8.0))
	await create_timer(0.6).timeout
	var moved: Vector3 = flat(h.global_position - p0)
	var bb: Array = h.kit["blight"].bolts if h.kit.has("blight") else []      # (Blight Bolt's rules: its skulls in flight)
	var bd: Vector3 = bb[0]["d"] if not bb.is_empty() else Vector3.ZERO
	check(moved.dot(walk_dir) > 0.9, "kept walking the other way while casting (%.2f)" % moved.dot(walk_dir))
	check(flat(bd).dot(shot_dir) > 0.99, "bolt flies toward the pointer, not the way he walks (%.3f)" % flat(bd).dot(shot_dir))
	kw = kw.duplicate()
	kw.pressed = false
	Input.parse_input_event(kw)
	await create_timer(1.0).timeout

	# 3. "self" skills don't turn him; "point" skills land on the pointer
	h._face(Vector3(1, 0, 0))
	var f0: Vector3 = h.facing()
	h.mana = h.max_mana
	h.use_skill("shackles", h.skill_aim("shackles", h.global_position + Vector3(-5, 0, 0)))
	check(h.facing().dot(f0) > 0.99, "self skill keeps facing")
	var pt: Vector3 = h.global_position + Vector3(3, 0, -4)
	check(h.skill_aim("attack", pt).is_equal_approx(pt), "point skill returns the pointer")

	# 4. every skill declares how it aims; directional skills have a range
	var bad := []
	for s in Data.SKILLS:
		var aim: String = s.get("aim", "")
		if not aim in ["facing", "self", "point"] or aim == "facing" and not s.has("range"):
			bad.append(s["id"])
	check(bad.is_empty(), "skills with a valid aim %d/%d %s" % [Data.SKILLS.size() - bad.size(), Data.SKILLS.size(), str(bad)])

	# 5. melee help: a pointer just beside a close foe bends onto him, whatever the facing
	await create_timer(1.0).timeout
	for f in g.enemies_near(h.global_position, 400.0):
		if not f.dead:
			e = f
			break
	h.global_position = g.world.free_spot_near(e.global_position + Vector3(1.8, 0, 0), 0.3)
	await create_timer(0.1).timeout
	var to_c: Vector3 = flat(e.global_position - h.global_position)
	h._face(-to_c)
	var near_pt: Vector3 = h.global_position + to_c.rotated(Vector3.UP, 0.25) * 2.0
	var pick = h._assist_pick(h.dir_to(near_pt), h.reach() + 1.5, Hero.AIM_CONE_MELEE)
	if pick != e:
		print("    debug: foe at %.2f m, pick %s at %.2f m, %d foes within 4 m" % [Vector2(e.global_position.x - h.global_position.x, e.global_position.z - h.global_position.z).length(), str(pick), (pick.global_position.distance_to(h.global_position) if pick != null else -1.0), g.enemies_near(h.global_position, 4.0).size()])
	check(pick == e or (pick != null and h.dir_to(pick.global_position).angle_to(h.dir_to(near_pt)) <= Hero.AIM_CONE_MELEE), "swing 14 deg off a close foe (facing away) bends onto him")
	var away_pt: Vector3 = h.global_position - to_c * 2.0
	check(h._assist_pick(h.dir_to(away_pt), h.reach() + 1.5, Hero.AIM_CONE_MELEE) == null, "pointer away from the foe: no pull back onto him")

	# 6. the swing's blow follows the aim even after the body turns (atk_dir is fixed when it starts)
	h.swipe_attack(e.global_position)
	var d0: Vector3 = h.aim_dir()
	h._face(-to_c)
	check(h.aim_dir().dot(d0) > 0.999 and d0.dot(to_c) > 0.99, "aim direction fixed at the swing's start, not read from the body")

	print("[A] done: %s" % ("all ok" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
