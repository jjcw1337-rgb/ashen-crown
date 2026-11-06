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
var failures := 0
const OUT := "res://scripts/skill_warm_data.gd"

func _initialize():
	if not OS.get_user_data_dir().get_file().begins_with("AshenCrown-"):
		push_error("Capture requires isolated AshenCrown-* user data")
		quit(2)
		return
	BuildEnv.forced = {"env": "local", "cloud": "0"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://warm_capture_characters/"
	g.old_save = g.char_dir + "absent.json"
	get_root().add_child(g)
	current_scene = g
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
	var args := OS.get_cmdline_user_args()
	var selected: Array = Array(args[args.find("--classes") + 1].split(",")) if args.has("--classes") else Data.CLASSES.keys()
	var out: Dictionary = SkillWarmData.EVENTS.duplicate(true)
	var pd_out: Array = [] if selected.has("plague") else SkillWarmData.PLAGUE.duplicate()
	for cls in Data.CLASSES.keys():
		if not selected.has(cls): continue
		await g.start_game(false, cls)
		g.ui.close_all()
		await g.travel(0, "wild", "start")
		while g._busy:
			await process_frame
		g.exit_grace = 1e9
		var h = g.hero
		# Run skills are absent from a story character's usable skill list.
		h.run = RunBuild.new()
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
			# Detonation needs branded targets to draw its actual explosion variant.
			if id == "d_detonate":
				for foe in en:
					DemonSkills.brand(h, foe)
			events.clear()
			pd_events.clear()
			var origin: Vector3 = h.global_position
			if id == "attack":
				h.swipe_attack(en[1].global_position, false)
			else:
				if Data.run_skills_for(cls).any(func(x): return x["id"] == id) and not h.run.skills.has(id):
					h.run.skills.append(id)
				if not h.use_skill(id, h.skill_aim(id, en[1].global_position)):
					push_error("Capture could not cast %s/%s" % [cls, id])
					failures += 1
			await wait(2.2)
			if id in ["k_aegis", "r_deathmark", "s_tomb", "v_cloud"]:
				# Wait for the real delayed event before clearing state or starting another skill.
				var late_phase: String = {"k_aegis": "burst", "r_deathmark": "pop", "s_tomb": "shatter", "v_cloud": "end"}[id]
				var deadline := Time.get_ticks_msec() + 30000
				while not events.any(func(w): return w.get("s") == id and w.get("e") == late_phase) and Time.get_ticks_msec() < deadline:
					await process_frame
				if not events.any(func(w): return w.get("s") == id and w.get("e") == late_phase):
					push_error("Capture missing delayed phase %s/%s" % [id, late_phase])
					failures += 1
			if id == "d_detonate" and not events.any(func(w): return w.get("s") == id and w.get("e") == "impact" and not w.get("ps", []).is_empty()):
				push_error("Capture missing branded Detonation impacts")
				failures += 1
			if str(id).begins_with("k_"):
				for phase in (["impact", "burst"] if id == "k_aegis" else ["impact"]):
					if not events.any(func(w): return w.get("s") == id and w.get("e") == phase):
						push_error("Capture missing Knight phase %s/%s" % [id, phase])
						failures += 1
			if id == "drain":
				h.end_drain()
			if id != "attack" and not events.any(func(w): return str(w.get("s", "")) == id):
				push_error("Capture missing event for %s/%s" % [cls, id])
				failures += 1
			for w in events:
				var pw = _plain(w, origin)
				if pw is Dictionary and pw.has("s") and pw.has("e"):
					mine.append(pw)
			for ev in pd_events:
				pd_out.append(_rel(str(ev), origin))
			SkillFx.clear(h)
			WraithSkills.clear(h)
			DemonSkills.clear(h)
			if h.pd != null:
				h.pd.clear()
			h.atk_t = -1.0
			await wait(0.3)
		out[cls] = mine
		print("[W] %s: %d events from %d skills" % [cls, mine.size(), ids.size()])
	if failures:
		printerr("Capture rejected; existing recipes preserved")
		quit(1)
		return
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("class_name SkillWarmData\nextends RefCounted\n## What every class's skills draw, recorded by tools/skill_warm_capture.gd (their fx events, places relative to the\n## caster, no monsters) for SkillWarm. Generated: run the capture again after changing a skill's effects.\n\nconst EVENTS := " + JSON.stringify(out) + "\n\n## The Plague Doctor's own events (Plague._send), places as \"~x,y,z\" relative to the caster.\nconst PLAGUE := " + JSON.stringify(pd_out) + "\n")
	f.close()
	print("[W] wrote ", OUT)
	g.queue_free()
	for i in 10: await process_frame
	quit()
