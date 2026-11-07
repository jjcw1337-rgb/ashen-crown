extends SceneTree
## What a skill deals: each skill cast at one durable dummy, its damage over the cast and the next WINDOW seconds
## (burns, tethers and lingering hits included), averaged over CASTS casts, per cast and per second of its cycle
## (the longer of its use time and its cooldown). For tuning skills the Path of Exile way (docs/content/skills.md, "Designing a skill").
##   godot --headless --path . -s tools/skill_dps.gd -- out.json [level] [class ...]
## Every class by default, at level 20 with its starting weapon; the shared skills on the knight.
const CASTS := 4
const WINDOW := 3.5

var g

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _run() -> void:
	while g.world == null or g._busy or g._intro_playing or not g.ui.title_panel.visible:
		g._intro_skip = true
		await process_frame
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://skill_dps.json"
	var lvl := int(a[1]) if a.size() > 1 and a[1].is_valid_int() else 20
	var classes: Array = a.slice(2) if a.size() > 2 else Data.CLASSES.keys()
	var res := {}
	for cls in classes:
		await g.start_game(false, cls)
		g.ui.close_all()
		await g.travel(0, "sandbox", "start")
		while g._busy:
			await process_frame
		var h = g.hero
		h.set_level(lvl)
		g.test_immortal = true
		var list: Array = Data.skills_for(cls) + (Data.shared_skills() if cls == "knight" else [])
		for sk in list:
			var id: String = sk["id"]
			var total := 0.0
			var n := 0
			for i in CASTS:
				var home: Vector3 = h.global_position
				var e = g.spawn_enemy("zombie", home + Vector3(0, 0, -2.6), lvl)
				if e == null:
					continue
				e.max_life = 1e7
				e.life = 1e7
				e.dmg = [0, 0]
				await create_timer(0.25).timeout
				h._face(Vector3(0, 0, -1))
				h.mana = h.max_mana
				h.buff_t = 0.0
				for k in h.cds.keys():
					h.cds[k] = 0.0
				var ok: bool = h.use_skill(id, h.skill_aim(id, e.global_position))
				var t0 := Time.get_ticks_msec()
				while Time.get_ticks_msec() - t0 < int((h.atk_dur + WINDOW) * 1000.0):
					if id == "drain" or (sk.get("channel", false)):
						h.drain_t = maxf(h.drain_t, 0.1)      # (a channel held for the whole window)
					await process_frame
				if ok and is_instance_valid(e):
					total += 1e7 - e.life
					n += 1
				if is_instance_valid(e):
					e.queue_free()
				h.end_drain()
				await create_timer(0.3).timeout
			var use_t := SkillSpec.use_time(h, id) if sk.has("use") else float(h.atk_dur)
			var cycle := maxf(use_t, h.skill_cd(id))
			var per := total / maxf(1.0, n)
			res[id] = {"cls": cls, "per_cast": snappedf(per, 0.1), "use": snappedf(use_t, 0.01), "cd": h.skill_cd(id),
				"cycle": snappedf(cycle, 0.01), "dps": snappedf(per / maxf(cycle, 0.1), 0.1), "casts": n}
			print("[DPS] %-8s %-13s per cast %7.1f  use %.2f  cd %4.1f  dps %6.1f" % [cls, id, per, use_t, h.skill_cd(id), per / maxf(cycle, 0.1)])
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	quit()
