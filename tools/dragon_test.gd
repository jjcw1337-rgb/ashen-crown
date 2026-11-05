extends SceneTree
## The dragon classes (Obsidian Wyrm, Frost Serpent, Storm Wyvern): each starts, its body loads with its skeleton
## and the joints the hero code reads, it walks and sprints (the legs, tail and body actually move), its basic attack
## (claw, bite, tail spin) hurts monsters with no weapon equipped, it blocks, dies and revives, its sounds are in the
## bank, and the class picker spreads the three round the ring with none side by side.
## Prints [G] lines ("FAIL" marks a check that failed).
##   godot --headless --path . -s tools/dragon_test.gd --fixed-fps 60
var g
var fails := 0
const KINDS := ["wyrm", "serpent", "wyvern"]

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[G] %s %s" % ["ok  " if ok else "FAIL", what])

func lives(en: Array) -> float:
	var t := 0.0
	for e in en:
		if is_instance_valid(e):
			t += e.life
	return t

func pack(at: Vector3, n: int, lvl := 5) -> Array:
	for e in g.enemies_near(at, 80.0):
		e.queue_free()
	await process_frame
	var out := []
	for i in n:
		var e = g.spawn_enemy("zombie", at + Vector3(-1.4 + i * 1.4, 0, 0), lvl)
		e.aggro = false
		e.scripted = 99.0
		e.max_life = 5000.0
		e.life = 5000.0
		out.append(e)
	await process_frame
	return out

## The sum of the leg bones' turns away from their rest (radians): how hard the legs are working right now.
func posed(h) -> float:
	var sk: Skeleton3D = h.rig.get_meta("drg_sk")
	var info: Dictionary = h.rig.get_meta("drg_info")
	var tot := 0.0
	for b in info:
		if not str(b).begins_with("leg_"):
			continue
		var e: Array = info[b]
		tot += (sk.get_bone_pose_rotation(int(e[0])) * (e[1] as Quaternion).inverse()).get_angle()
	return tot

func tail_turn(h) -> float:
	var sk: Skeleton3D = h.rig.get_meta("drg_sk")
	var info: Dictionary = h.rig.get_meta("drg_info")
	var e: Array = info["tail_3"]
	return (sk.get_bone_pose_rotation(int(e[0])) * (e[1] as Quaternion).inverse()).get_angle()

func _run() -> void:
	while g.world == null or g._busy:
		await process_frame
	# --- the class picker's ring
	var ring: Array = ClassStage.CLASSES
	for c in KINDS:
		check(ring.has(c), "%s is in the class picker" % c)
		check(Data.CLASSES.has(c), "%s is a class (%s)" % [c, str(Data.CLASSES.get(c, {}).get("name", "?"))])
		check(ClassStage.ACCENTS.has(c) and ClassStage.EMBLEMS.has(c) and ClassStage.SIGNATURE.has(c) and ClassStage.PICK_SOUND.has(c), "%s has its stand, signature and pick sound" % c)
	var n := ring.size()
	var apart := true
	for i in n:
		if Dragon.is_dragon(ring[i]) and Dragon.is_dragon(ring[(i + 1) % n]):
			apart = false
	check(apart, "no two dragons stand side by side in the ring %s" % str(ring))
	# the bank read from its script (the Sfx autoload isn't known while a -s tool compiles)
	var bank: Dictionary = load("res://scripts/sfx_bank.gd").BANK
	for c in KINDS:
		for s in ["_step", "_claw", "_bite", "_tail", "_roar"]:
			check(bank.has(c + s), "sound %s%s in the bank" % [c, s])
		check(bank.has("death_" + c), "sound death_%s in the bank" % c)
	check(bank.has("wyvern_flap"), "sound wyvern_flap in the bank")

	var first := true
	for c in KINDS:
		if first:
			await g.start_game(false, c)
			first = false
		else:
			g.hero.set_class(c)
			g.hero.new_character()
		var h = g.hero
		print("[G] --- ", c)
		check(h.cls == c and h.is_dragon(), "%s started" % c)
		check(h.rig.has_meta("dragon") and h.rig.has_meta("drg_sk"), "its body loaded with a skeleton (glb %s)" % str(Dragon.ok(c)))
		var info: Dictionary = h.rig.get_meta("drg_info") if h.rig.has_meta("drg_info") else {}
		check(info.has("spine_0") and info.has("tail_3") and info.has("head_0") and info.has("jaw_0"), "bones found (%d)" % info.size())
		var J: Dictionary = h.rig.get_meta("j")
		for k in ["head", "grip_r", "grip_l", "mount_l", "chest", "torso", "hand_r", "hand_l"]:
			check(J.has(k), "joint %s" % k)
		check(h.equipment["weapon"] == null, "starts with its own claws (no weapon)")
		check(h.dmg_max >= 5, "claw damage %d-%d" % [h.dmg_min, h.dmg_max])
		# its own skills (the wyrm has none yet; the serpent breathes frost, the wyvern Storm Arc), on Q by default
		var own: Array = Data.skills_for(c)
		var want_q: String = str(own[0]["id"]) if not own.is_empty() else ""
		check(h.skill_list().size() == own.size() and h.bound("lmb") == "attack" and (want_q == "" or h.bound("Q") == want_q),
			"its skills %s; left mouse attacks" % [own.map(func(x): return x["id"])])
		check(h.reach() > 1.9, "a long reach (%.1f m)" % h.reach())
		if first == false and c == KINDS[0]:
			await g.travel(0, "wild", "start")
			while g._busy:
				await process_frame
		g.test_immortal = true
		g.playing = false        # Game._process would overwrite blocking, sprint and WASD from the real keyboard
		var home: Vector3 = h.global_position
		# standing: the tail is never still
		await wait(0.5)
		var t0: float = tail_turn(h)
		await wait(0.45)
		check(absf(tail_turn(h) - t0) > 0.02, "the tail wags at rest (%.3f)" % absf(tail_turn(h) - t0))
		var rest_pose := posed(h)
		# walking, then sprinting: the hero moves and the body is posed more than at rest
		h.direct_dir = Vector3(1, 0, 0)
		await wait(0.8)
		var walk_pose := posed(h)
		h.sprint = true
		await wait(0.8)
		var went: float = home.distance_to(h.global_position)
		var run_pose := posed(h)
		h.direct_dir = Vector3.ZERO
		h.sprint = false
		check(went > 4.0, "it ran %.1f m" % went)
		check(walk_pose > rest_pose * 1.05 or run_pose > rest_pose * 1.2, "the legs work harder moving (rest %.2f walk %.2f run %.2f)" % [rest_pose, walk_pose, run_pose])
		await wait(0.6)
		# the basic attack: three swipes (claw, bite, tail spin) on a pack in front
		home = h.global_position
		var en: Array = await pack(home + Vector3(0, 0, -2.0), 3)
		h._face(Vector3(0, 0, -1))
		var l0 := lives(en)
		for i in 3:
			h.swipe_attack(home + Vector3(0, 0, -2.0), false)
			await wait(1.05)
		check(lives(en) < l0 - 5.0, "claw, bite and tail spin hurt the pack (%d)" % int(l0 - lives(en)))
		var spun: float = (h.rig.get_meta("drg_hold") as Node3D).rotation.y
		check(absf(spun) < 0.05 or absf(spun - TAU) < 0.05, "the spin came back round (%.2f)" % spun)
		# block
		h.blocking = true
		await wait(0.4)
		check(h.block_amt > 0.5, "it blocks")
		h.blocking = false
		await wait(0.3)
		# death and revive
		g.test_immortal = false
		h.take_hit(99999.0, h.global_position + Vector3(0, 0, -1))
		await wait(1.5)
		check(h.dead, "it dies")
		var roll: float = (h.rig.get_meta("drg_hold") as Node3D).rotation.z
		check(roll > 0.8, "and falls onto its side (%.2f)" % roll)
		g.respawn()
		await wait(1.0)
		check(not h.dead, "and comes back")
		g.test_immortal = true
		for e in en:
			if is_instance_valid(e):
				e.queue_free()
	print("[G] done, %d failed" % fails)
	quit(1 if fails > 0 else 0)
