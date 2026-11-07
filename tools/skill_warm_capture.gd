extends SceneTree
## Records what every class's skills draw (their fx events, as they go on the wire) so SkillWarm can replay them
## during the loading screen and the graphics driver compiles every effect's shaders and loads its models before the
## first cast (jj, 2026-11-04: "intense lag and freezing" on a first Fire Arrow and other skills: 0.1-0.5 s).
## Each class plays its weapon attack and every skill beside a pack of zombies; the events are stored with their
## places relative to the caster (facing -z) and without the monsters they touched.
##   godot --headless --path . -s tools/_late.gd -- res://tools/skill_warm_capture.gd
## Writes res://scripts/skill_warm_data.gd (SkillWarmData.EVENTS: a script, so the exported game carries it).

var g
var events: Array = []
var pd_events: Array = []      # the Plague Doctor's own events (Plague._send), replayed on a puppet's ghost Plague
const OUT := "res://scripts/skill_warm_data.gd"

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func pack(at: Vector3, n: int) -> Array:
	for e in g.enemies_near(at, 60.0):
		e.queue_free()
	await process_frame
	var out := []
	for i in n:
		var e = g.spawn_enemy("zombie", at + Vector3(-1.0 + i * 1.0, 0, 0), 18)
		e.aggro = false
		out.append(e)
	await process_frame
	return out

## A value as JSON: places relative to the caster, the monsters dropped.
func _plain(v, origin: Vector3):
	if v is Vector3:
		var r: Vector3 = v - origin
		return {"v3": [r.x, r.y, r.z]}
	if v is PackedVector3Array:
		var a := []
		for p in v:
			var r: Vector3 = p - origin
			a.append([r.x, r.y, r.z])
		return {"pv3": a}
	if v is PackedInt64Array or v is Object:
		return null
	if v is Array:
		var a2 := []
		for x in v:
			var px = _plain(x, origin)
			if px != null:
				a2.append(px)
		return a2
	if v is Dictionary:
		var d := {}
		for k in v:
			var px = _plain(v[k], origin)
			if px != null:
				d[k] = px
		return d
	if v is float or v is int or v is bool or v is String or v is StringName:
		return v
	return null

## A Plague event with its places ("x,y,z") made relative to the caster ("~x,y,z").
func _rel(ev: String, origin: Vector3) -> String:
	var a := ev.split("|")
	for i in a.size():
		var v := a[i].split(",")
		if v.size() == 3 and v[0].is_valid_float() and v[1].is_valid_float() and v[2].is_valid_float():
			var r := Vector3(float(v[0]), float(v[1]), float(v[2])) - origin
			a[i] = "~%.2f,%.2f,%.2f" % [r.x, r.y, r.z]
	return "|".join(a)

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	g.net.fx_tap = func(w: Dictionary): events.append(w)
	g.net.pd_tap = func(ev: String): pd_events.append(ev)
	g.test_immortal = true
	g.test_allskills = true
	var out := {}
	var pd_out: Array = []
	for cls in Data.CLASSES.keys():
		await g.start_game(false, cls)
		g.ui.close_all()
		await g.travel(0, "sandbox", "start")
		while g._busy:
			await process_frame
		g.exit_grace = 1e9
		var h = g.hero
		h.level = 20
		h.recalc()
		var ids: Array = ["attack"]
		for sk in Data.skills_for(cls) + Data.run_skills_for(cls) + Data.shared_skills():
			ids.append(str(sk["id"]))
		var mine: Array = []
		for id in ids:
			var en: Array = await pack(h.global_position + Vector3(0, 0, -3.5), 3)
			h._face(Vector3(0, 0, -1))
			for k in h.cds.keys():
				h.cds[k] = 0.0
			h.mana = h.max_mana
			h.life = h.max_life
			events.clear()
			pd_events.clear()
			var origin: Vector3 = h.global_position
			if id == "attack":
				h.swipe_attack(en[1].global_position, false)
			else:
				if Data.run_skills_for(cls).any(func(x): return x["id"] == id):
					# a run's skill: only a run character has it
					h.run = load("res://game/items/run_build.gd").new()
					h.run.skills.append(id)
				h.use_skill(id, h.skill_aim(id, en[1].global_position))
				h.run = null
			await wait(2.2)
			if id == "drain":
				h.end_channel()
			for w in events:
				var pw = _plain(w, origin)
				if pw is Dictionary and pw.has("s") and pw.has("e"):
					mine.append(pw)
			for ev in pd_events:
				pd_out.append(_rel(str(ev), origin))
			SkillFx.clear(h)
			WraithSkills.clear(h)
			Demon.clear(h)
			if h.pd != null:
				h.pd.clear()
			h.atk_t = -1.0
			await wait(0.3)
		out[cls] = mine
		print("[W] %s: %d events from %d skills" % [cls, mine.size(), ids.size()])
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("class_name SkillWarmData\nextends RefCounted\n## What every class's skills draw, recorded by tools/skill_warm_capture.gd (their fx events, places relative to the\n## caster, no monsters) for SkillWarm. Generated: run the capture again after changing a skill's effects.\n\nconst EVENTS := " + JSON.stringify(out) + "\n\n## The Plague Doctor's own events (Plague._send), places as \"~x,y,z\" relative to the caster.\nconst PLAGUE := " + JSON.stringify(pd_out) + "\n")
	f.close()
	print("[W] wrote ", OUT)
	quit()
