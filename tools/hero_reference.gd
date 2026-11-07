extends SceneTree
## Any hero's reference, for rebuilding a hero without changing play (docs/content/skills.md): every skill of the
## class (its own kit, then a run's skills) cast at the same still training dummies with the dice taken out (no
## crits, a fixed damage roll), and what each did to each dummy: the damage, the longest burn, stun and chill, and
## the hero's battle buff. The same fixed layout for every class (dummies close, mid, far and to the sides; aimed at
## the middle), so a skill's record means nothing on its own: it is only ever compared with itself.
## It reaches the Sfx autoload, so it runs through tools/_late.gd:
##   godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/hero_reference.gd <class>         (compare)
##   godot --headless --path . --fixed-fps 60 -s tools/_late.gd -- res://tools/hero_reference.gd <class> record  (rewrite)
## The record is tools/references/<class>.json. A skill whose record isn't the same twice running (a summon's brain,
## a random gag) is marked "loose" when recorded and only checked for having done something.
## Prints [HR] lines.

const ROLL := 100.0
const TOL := 0.015
const SETTLE := 360

var g
var fails := 0
var cls := ""
var record := false
var results := {}

func _initialize():
	var args := OS.get_cmdline_user_args()
	record = "record" in args
	for a in args:
		if not a.begins_with("res://") and a != "record":
			cls = a
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[HR] %s %s" % ["ok  " if ok else "FAIL", what])

func frames(n: int) -> void:
	for i in n:
		await process_frame

func _path() -> String:
	return "res://tools/references/%s.json" % cls

func _dummy(at: Vector3) -> Enemy:
	at.y = g.world.height_at(at.x, at.z)
	var e: Enemy = g.spawn_enemy("zombie", at, 3)
	e.speed = 0.0
	e.max_life = 1000000.0
	e.life = e.max_life
	return e

func _ready_hero(h, p0: Vector3, fwd: Vector3) -> void:
	g.exit_grace = 1e9
	ClassSkills.clear(h)
	h.global_position = p0
	h.moving = false
	h.path = PackedVector3Array()
	h.target = null
	h._face(fwd)
	h.dex = -100
	h.recalc()
	h.dmg_min = ROLL
	h.dmg_max = ROLL
	h.fire_dmg = 0.0
	h.buff_t = 0.0
	h.mana = h.max_mana
	h.life = h.max_life
	h.cds.clear()
	for b in h.beasts:
		if is_instance_valid(b):
			b.queue_free()
	h.beasts.clear()
	h.beast_down_t = 1e9

func _case(h, name: String, skill: String, p0: Vector3, fwd: Vector3) -> void:
	_ready_hero(h, p0, fwd)
	var side := Vector3(fwd.z, 0, -fwd.x)
	var spots := [p0 + fwd * 2.5, p0 + fwd * 5.0, p0 + fwd * 8.0, p0 + fwd * 8.0 + side * 2.5, p0 + fwd * 8.0 - side * 2.5, p0 + fwd * 11.0]
	var foes := spots.map(func(p: Vector3) -> Enemy: return _dummy(p))
	await frames(2)
	var peak := foes.map(func(_e) -> Dictionary: return {"burn": 0.0, "stun": 0.0, "chill": 0.0})
	var aim: Vector3 = p0 + fwd * 7.0
	if skill == "attack":
		h.swipe_attack(aim)
	else:
		h.use_skill(skill, aim)
	var buff := 0.0
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
	var row := []
	for k in foes.size():
		var e: Enemy = foes[k]
		var dmg := snappedf(e.max_life - e.life, 0.1) if is_instance_valid(e) else -1.0
		row.append({"dmg": dmg, "burn": snappedf(peak[k]["burn"], 0.1), "stun": snappedf(peak[k]["stun"], 0.1),
			"chill": snappedf(peak[k]["chill"], 0.01)})
		if is_instance_valid(e):
			e.queue_free()
	ClassSkills.clear(h)
	results[name] = {"foes": row, "buff": snappedf(buff, 0.1)}
	print("[HR] %-14s %s buff %.1f" % [name, row.map(func(r): return "%.0f/b%.1f/s%.1f/c%.2f" % [r.dmg, r.burn, r.stun, r.chill]), buff])
	await frames(2)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	g.test_immortal = true
	g.test_allskills = true
	await g.load_zone(0, "sandbox", "start")
	for e in g.world.enemies_root.get_children():
		e.queue_free()
	await frames(2)
	var h = g.hero
	check(h.cls == cls, "the hero is a %s" % cls)
	h.level = 12
	var p0: Vector3 = h.global_position
	var fwd: Vector3 = -h.rig.global_transform.basis.z
	fwd = Vector3(fwd.x, 0, fwd.z).normalized()
	await _case(h, "attack", "attack", p0, fwd)
	for s in Data.SKILLS:
		if str(s.get("cls", "")) == cls:
			await _case(h, str(s["id"]), str(s["id"]), p0, fwd)
	var run_ids := []
	for s in Data.RUN_SKILLS:
		if str(s.get("cls", "")) == cls:
			run_ids.append(str(s["id"]))
	if not run_ids.is_empty():
		h.start_run()
		h.level = 12
		await _case(h, "run_attack", "attack", p0, fwd)
		for id in run_ids:
			await _case(h, id, id, p0, fwd)
	if record:
		_record()
	else:
		_compare()
	print("[HR] done, %d failed" % fails)
	quit()

## Recording runs every case twice more and marks a case "loose" when they disagree.
func _record() -> void:
	var old = JSON.parse_string(FileAccess.get_file_as_string(_path())) if FileAccess.file_exists(_path()) else null
	var keep := {}
	for name in results:
		keep[name] = results[name].duplicate(true)
		if old is Dictionary and old.has(name) and not _same(results[name], old[name]):
			keep[name]["loose"] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/references"))
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(keep, "\t", true) + "\n")
	f.close()
	print("[HR] recorded %d cases to %s (record twice: the second marks the unsteady ones loose)" % [keep.size(), _path()])

func _near(a: float, b: float, rel: float, abs_tol: float) -> bool:
	return absf(a - b) <= maxf(abs_tol, absf(b) * rel)

func _same(got: Dictionary, want: Dictionary) -> bool:
	if got["foes"].size() != want["foes"].size() or not _near(float(got["buff"]), float(want["buff"]), 0.0, 0.15):
		return false
	for k in got["foes"].size():
		var a: Dictionary = got["foes"][k]
		var b: Dictionary = want["foes"][k]
		if not (_near(a.dmg, b.dmg, TOL, 1.0) and _near(a.burn, b.burn, 0.0, 0.15) and _near(a.stun, b.stun, 0.0, 0.15) and _near(a.chill, b.chill, 0.0, 0.02)):
			return false
	return true

func _compare() -> void:
	var ref = JSON.parse_string(FileAccess.get_file_as_string(_path())) if FileAccess.file_exists(_path()) else null
	check(ref is Dictionary, "the reference is there (%s)" % _path())
	if not ref is Dictionary:
		return
	for name in ref:
		var want: Dictionary = ref[name]
		var got: Dictionary = results.get(name, {})
		if got.is_empty():
			check(false, "%s was cast" % name)
			continue
		if want.get("loose", false):
			var did := false
			for r in got["foes"]:
				did = did or float(r.dmg) > 0.0 or float(r.stun) > 0.0 or float(r.chill) > 0.0 or float(r.burn) > 0.0
			check(did or float(got["buff"]) > 0.0 or not want["foes"].any(func(r): return float(r.dmg) > 0.0), "%s (loose) still does something" % name)
			continue
		check(_same(got, want), "%s matches (got %s, want %s)" % [name, got["foes"].map(func(r): return r.dmg), want["foes"].map(func(r): return r.dmg)])
