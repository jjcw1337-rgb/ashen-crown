extends SceneTree
## The Archer's reference (his rebuild into skill objects, docs/content/skills.md): every skill cast at still
## training dummies with the dice taken out (no crits, a fixed damage roll), and what each one did to each dummy:
## the damage, the longest burn, stun and chill. The rebuild must reproduce it, so moving code can't change play
## unnoticed. The wolf is kept away (its bites aren't recorded); Spirit Beast records its buff and mark.
## It reaches the Sfx autoload, so it runs through tools/_late.gd:
##   godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://game/heroes/archer/tests/archer_reference.gd
##   (add `record` after it to rewrite the reference)
## Prints [R] lines.

const REF := "res://game/heroes/archer/tests/archer_reference.json"
## A fixed roll is dmg_min..dmg_max + 1 (Hero.roll_damage), so 100 leaves at most 1% of noise; allow 1.5%.
const ROLL := 100.0
const TOL := 0.015
const SETTLE := 360           # frames after each cast: burns, the frozen ground and the sigil have all ended

var g
var fails := 0
var record := false
var results := {}

func _initialize():
	record = "record" in OS.get_cmdline_user_args()
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[R] %s %s" % ["ok  " if ok else "FAIL", what])

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _dummy(at: Vector3) -> Enemy:
	at.y = g.world.height_at(at.x, at.z)
	var e: Enemy = g.spawn_enemy("zombie", at, 3)
	e.speed = 0.0                 # stands where it was put
	e.max_life = 1000000.0
	e.life = e.max_life
	return e

## The hero back on his mark, facing the same way, rested, with no dice.
func _ready_hero(h, p0: Vector3, fwd: Vector3) -> void:
	g.exit_grace = 1e9            # (the vault mustn't carry him through a zone exit)
	Archer.clear(h)
	h.global_position = p0
	h.moving = false
	h.path = PackedVector3Array()
	h.target = null
	h._face(fwd)
	h.dex = -100                  # crit chance below zero (Hero.roll_damage)
	h.recalc()
	h.dmg_min = ROLL
	h.dmg_max = ROLL
	h.fire_dmg = 0.0
	h.buff_t = 0.0
	h.mana = h.max_mana
	h.cds.clear()
	for b in h.beasts:
		if is_instance_valid(b):
			b.queue_free()
	h.beasts.clear()
	h.beast_down_t = 1e9          # his wolf stays away: its bites aren't part of the record

## Casts one skill at its dummies and records what each one took.
func _case(h, name: String, skill: String, aim: Vector3, spots: Array, p0: Vector3, fwd: Vector3) -> void:
	_ready_hero(h, p0, fwd)
	var foes := spots.map(func(p: Vector3) -> Enemy: return _dummy(p))
	await frames(2)
	var peak := foes.map(func(_e) -> Dictionary: return {"burn": 0.0, "stun": 0.0, "chill": 0.0})
	if skill == "attack":
		h.swipe_attack(aim)
	else:
		h.use_skill(skill, aim)
	var buff := 0.0
	var marked := false
	for i in SETTLE:
		await process_frame
		buff = maxf(buff, h.buff_t)
		for k in foes.size():
			var e: Enemy = foes[k]
			if not is_instance_valid(e):
				continue
			peak[k]["burn"] = maxf(peak[k]["burn"], e.burn_t)
			peak[k]["stun"] = maxf(peak[k]["stun"], e.stun_t)
			peak[k]["chill"] = maxf(peak[k]["chill"], e.chill_k if e.chill_t > 0.0 else 0.0)
			marked = marked or e.has_meta("hunted_until")
	var row := []
	for k in foes.size():
		var e: Enemy = foes[k]
		row.append({"dmg": snappedf(e.max_life - e.life, 0.1), "burn": snappedf(peak[k]["burn"], 0.1),
			"stun": snappedf(peak[k]["stun"], 0.1), "chill": snappedf(peak[k]["chill"], 0.01)})
		e.queue_free()
	results[name] = {"foes": row, "buff": snappedf(buff, 0.1), "marked": marked}
	print("[R] %-12s %s buff %.1f marked %s" % [name, row.map(func(r): return "%.1f/b%.1f/s%.1f/c%.2f" % [r.dmg, r.burn, r.stun, r.chill]), buff, marked])
	await frames(2)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "archer")
	g.test_immortal = true
	g.test_allskills = true
	await g.load_zone(0, "wild", "start")
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await frames(2)
	var h = g.hero
	h.level = 12
	var p0: Vector3 = h.global_position
	var fwd: Vector3 = -h.rig.global_transform.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	var side := Vector3(fwd.z, 0, -fwd.x)
	var ring := func(c: Vector3, r: float) -> Array:
		return [c + side * r, c - side * r * 0.5 + fwd * r * 0.87, c - side * r * 0.5 - fwd * r * 0.87]

	# his own kit (Enter World: level 12, no run)
	await _case(h, "attack", "attack", p0 + fwd * 9.0, [p0 + fwd * 9.0], p0, fwd)
	await _case(h, "pierce", "pierce", p0 + fwd * 12.0, [p0 + fwd * 5.0, p0 + fwd * 7.5, p0 + fwd * 10.0], p0, fwd)
	await _case(h, "volley", "volley", p0 + fwd * 8.0, ring.call(p0 + fwd * 8.0, 2.0), p0, fwd)
	await _case(h, "snare", "snare", p0 + fwd * 6.0, [p0 + fwd * 1.4, p0 + fwd * 5.5], p0, fwd)
	await _case(h, "beast", "beast", p0 + fwd * 4.0, [p0 + fwd * 4.0], p0, fwd)

	# a run's skills (a run: level 12 again after start_run resets it)
	h.start_run()
	h.level = 12
	await _case(h, "a_multishot", "a_multishot", p0 + fwd * 8.0, [p0 + fwd * 8.0 - side * 1.5, p0 + fwd * 8.0, p0 + fwd * 8.0 + side * 1.5], p0, fwd)
	await _case(h, "a_explosive", "a_explosive", p0 + fwd * 8.0, [p0 + fwd * 8.0, p0 + fwd * 8.0 + side * 2.0, p0 + fwd * 8.0 - side * 2.0], p0, fwd)
	await _case(h, "a_glacial", "a_glacial", p0 + fwd * 12.0, [p0 + fwd * 5.0, p0 + fwd * 7.5, p0 + fwd * 10.0], p0, fwd)
	await _case(h, "a_stormshot", "a_stormshot", p0 + fwd * 8.0, [p0 + fwd * 8.0, p0 + fwd * 8.0 + side * 3.0, p0 + fwd * 11.0, p0 + fwd * 8.0 - side * 3.0], p0, fwd)
	await _case(h, "a_barrage", "a_barrage", p0 + fwd * 8.0, ring.call(p0 + fwd * 8.0, 2.0), p0, fwd)
	await _case(h, "a_mark", "a_mark", p0 + fwd * 8.0, [p0 + fwd * 8.0], p0, fwd)
	await _case(h, "run_attack", "attack", p0 + fwd * 9.0, [p0 + fwd * 9.0], p0, fwd)

	if record:
		var f := FileAccess.open(REF, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "\t", true) + "\n")
		f.close()
		print("[R] recorded %d skills to %s" % [results.size(), REF])
	else:
		_compare()
	print("[R] done, %d failed" % fails)
	quit()

func _near(a: float, b: float, rel: float, abs_tol: float) -> bool:
	return absf(a - b) <= maxf(abs_tol, absf(b) * rel)

func _compare() -> void:
	var ref = JSON.parse_string(FileAccess.get_file_as_string(REF))
	check(ref is Dictionary, "the reference file is there (%s)" % REF)
	if not ref is Dictionary:
		return
	for name in ref:
		var want: Dictionary = ref[name]
		var got: Dictionary = results.get(name, {})
		if got.is_empty():
			check(false, "%s was cast" % name)
			continue
		var ok: bool = got["foes"].size() == want["foes"].size() and bool(got["marked"]) == bool(want["marked"]) \
			and _near(float(got["buff"]), float(want["buff"]), 0.0, 0.15)
		for k in mini(got["foes"].size(), want["foes"].size()):
			var a: Dictionary = got["foes"][k]
			var b: Dictionary = want["foes"][k]
			ok = ok and _near(a.dmg, b.dmg, TOL, 1.0) and _near(a.burn, b.burn, 0.0, 0.15) \
				and _near(a.stun, b.stun, 0.0, 0.15) and _near(a.chill, b.chill, 0.0, 0.02)
		check(ok, "%s matches the reference (got %s, want %s)" % [name, got["foes"].map(func(r): return r.dmg), want["foes"].map(func(r): return r.dmg)])
