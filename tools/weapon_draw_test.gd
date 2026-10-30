extends SceneTree
## Weapon draw / holster (WeaponCarry) in the real game: the knight in armour on the moor.
##   godot --headless --path . -s tools/weapon_draw_test.gd
## A targeted -> draws · B retreats while still hunted -> stays drawn, then holsters once safe ·
## C the foe gives up -> waits out the disengage time · D two foes, one gives up -> stays drawn ·
## E attacks while holstering -> armed at once · F a draw interrupted -> runs back without a jump ·
## town -> always away · a character with no profile -> the default draw, no crash ·
## the crusader's scabbard hilt hides while the sword is in his hand.
var g
var fails := 0
func ok(c: bool, what: String) -> void:
	print("[D] ", "ok   " if c else "FAIL ", what)
	if not c:
		fails += 1

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func secs(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await process_frame

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing:
		await process_frame
	await g.start_game(false, "knight")
	while g._busy:
		await process_frame
	var h = g.hero
	h.equipment["armor"] = Items.make("chain_mail")
	h.refresh_gear()
	await frames(5)
	ok(h.carry.p["motion"] == "knight" and h.carry.p["store"] == "hilt", "the knight uses his own profile (cross-body draw, scabbard)")
	# town: always away
	ok(g.cur_zone == "town" and h.carry.state == "sheathed", "in town the sword stays sheathed (%s)" % h.carry.state)
	g.travel(0, "wild", "waypoint")
	while g._busy:
		await process_frame
	await frames(10)
	# (a pack near the waypoint may have spotted him on arrival: clear the moor, then he should calm down)
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await frames(3)
	h.carry.state = "sheathed"
	h.carry.t = 0.0
	h.carry.safe_t = 99.0
	h.carry._scan = 0.0
	h.carry._threat = false
	await secs(0.6)
	ok(h.carry.state == "sheathed", "on the moor, with nothing hunting him: stays sheathed (%s)" % h.carry.state)
	ok(not h.weapon_node.visible, "the sword model is hidden in the scabbard")
	# A: a foe targets him -> draws
	var p: Vector3 = h.global_position + Vector3(6, 0, 0)
	var e1 = g.spawn_enemy("zombie", p, 1)
	e1.aggro = true
	e1.stun_t = 999.0           # it hunts him but stands still, so the test controls the distance
	await secs(0.4)
	ok(h.carry.state == "drawing" or h.carry.state == "drawn", "A: targeted -> he draws (%s)" % h.carry.state)
	await secs(1.0)
	ok(h.carry.state == "drawn" and h.weapon_node.visible and h.weapon_node.get_parent() == h.rig.get_meta("j")["grip_r"], "A: the sword is in his hand")
	# B: he steps out of its reach but it still hunts him -> stays drawn
	h.global_position = e1.global_position + Vector3(-11, 0, 0)
	await secs(1.0)
	ok(h.carry.state == "drawn", "B: out of reach but still hunted -> stays drawn")
	# D: a second foe hunts him; the first gives up -> still drawn
	var e2 = g.spawn_enemy("zombie", h.global_position + Vector3(0, 0, 7), 1)
	e2.aggro = true
	e2.stun_t = 999.0
	e1.aggro = false
	await secs(1.0)
	ok(h.carry.state == "drawn", "D: one foe gives up, another still hunts -> stays drawn")
	# C: both give up -> not at once; holsters after the disengage time
	e2.aggro = false
	await secs(1.5)
	ok(h.carry.state == "drawn", "C: just lost them -> waits before putting it away (%.1fs safe)" % h.carry.safe_t)
	await secs(3.4)
	ok(h.carry.state == "sheathing" or h.carry.state == "sheathed", "C: safe for the disengage time -> holsters (%s)" % h.carry.state)
	# E: attack while holstering -> armed at once
	await secs(0.2)
	h.atk_t = 0.0
	h.atk_dur = 0.6
	await frames(2)
	ok(h.carry.state == "drawn" and h.carry.t >= 1.0, "E: attacks mid-holster -> armed at once")
	h.atk_t = -1.0
	# F: interrupted draw runs back from where it was
	h.carry.state = "sheathed"
	h.carry.t = 0.0
	h.carry.safe_t = 0.0
	e1.aggro = true
	await secs(0.35)
	var mid: float = h.carry.t
	e1.aggro = false
	e1.queue_free()
	e2.queue_free()
	h.carry.safe_t = 99.0
	h.carry._scan = 0.0
	var peak := mid
	for i in 30:
		await process_frame
		peak = maxf(peak, h.carry.t)
		if h.carry.state == "sheathing":
			break
	var after: float = h.carry.t
	ok(mid > 0.05 and mid < 1.0 and h.carry.state == "sheathing" and peak - mid < 0.25 and after <= peak, "F: a draw cut short reverses from %.2f (turned at %.2f), no jump" % [mid, peak])
	await secs(1.2)
	ok(h.carry.state == "sheathed" and not h.weapon_node.visible, "F: and ends back in the scabbard")
	# the crusader's own hilt: shown while sheathed, hidden while the sword is in his hand
	var hilt_hidden := func() -> int:
		var n := 0
		for mi in h.rig.find_children("*", "MeshInstance3D", true, false):
			var m = (mi as MeshInstance3D).mesh
			if m:
				for si in m.get_surface_count():
					var mat = m.surface_get_material(si)
					if mat and mat.resource_name == "Hilt":
						n += 1 if (mi as MeshInstance3D).get_surface_override_material(si) != null else 0
		return n
	ok(hilt_hidden.call() == 0, "the scabbard hilt shows while sheathed")
	h.carry.state = "drawn"
	h.carry.t = 1.0
	await frames(3)
	ok(hilt_hidden.call() > 0, "the scabbard hilt hides while the sword is drawn (one sword, never two)")
	# a character with no profile: default draw, no crash
	var wc := WeaponCarry.new()
	wc.configure("no_such_character")
	ok(wc.p["motion"] == "back", "an unknown character gets the default draw (and a warning)")
	print("[D] done, %d failed" % fails)
	quit(1 if fails else 0)
