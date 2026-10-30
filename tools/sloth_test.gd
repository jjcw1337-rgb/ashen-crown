extends SceneTree
## The Hollow Sloths (sloth.gd): three roam the Act I moor, one each of fire, ice and lightning. Each wanders far on its own; one that sees a
## hero rises, stares, roars and comes, building into a run; its sweep throws the hero back, its slam
## stuns, its pounce leaps; badly hurt it runs off, a hero who gets away is given up on, and killing one
## drops a unique and its own material (picked up glowing, with its ting). Each element's skills do their
## thing: burning ground, a freeze, lightning bolts. The corner map marks one that's near. Prints [S] lines.
var g
var fails := 0

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("[S] %s %s" % ["ok  " if ok else "FAIL", what])

func _sloths() -> Array:
	return g.world.enemies_root.get_children().filter(func(e) -> bool: return e is Enemy and e.def.get("mesh", "") == "sloth" and not e.dead)

## Plays until cond is true or secs pass, noting every style the sloth shows.
func _until(s, secs: float, cond: Callable, seen: Dictionary) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < secs * 1000.0:
		await process_frame
		if not is_instance_valid(s):
			return false
		seen[s.atk_style] = true
		if cond.call():
			return true
	return false

func _run() -> void:
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, "knight")
	g.difficulty = 0
	g.test_immortal = true
	await g.load_zone(0, "wild", "start")
	await wait(0.3)
	var ss := _sloths()
	var spots := ss.map(func(e): return Vector2(e.global_position.x, e.global_position.z))
	var apart := true
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			if spots[i].distance_to(spots[j]) < 30.0:
				apart = false
	check(ss.size() == 3 and apart, "three Hollow Sloths on the moor, far apart: %s" % [spots.map(func(v): return "(%.0f, %.0f)" % [v.x, v.y])])
	var kinds := ss.map(func(e): return e.kind)
	kinds.sort()
	check(kinds == ["sloth_fire", "sloth_ice", "sloth_storm"], "one of each element: %s (%s)" % [kinds, ", ".join(ss.map(func(e): return e.display_name))])
	check(ss.size() > 0 and ss[0].rig.has_meta("sloth") and ss.all(func(e): return e.rig.has_meta("sloth_light")), "posed on their skeletons, lit in their colours (%s)" % ", ".join(ss.map(func(e): return "%s: %s" % [e.def["variant"], "Meshy model" if load("res://scripts/sloth.gd").ok(e.def["variant"]) else "stand-in"])))
	if ss.size() < 3:
		print("[S] done, %d failed" % (fails + 1))
		quit()
		return
	# the hero far away, out of everyone's sight: they roam on their own
	g.hero.global_position = Vector3(0, 0, -6)
	var start := ss.map(func(e): return e.global_position)
	var seen := {}
	var far_ok := await _until(ss[0], 25.0, func(): return ss.all(func(e): return e.global_position.distance_to(start[ss.find(e)]) > 8.0), seen)
	for e in ss:
		seen[e.atk_style] = true
	var moved := []
	for i in ss.size():
		moved.append("%.0f m" % ss[i].global_position.distance_to(start[i]))
	check(far_ok, "each roams off on its own while no one is near: moved %s" % [moved])
	# idling: a sniff or a rise to look about, given time
	var s = ss[0]
	s.sloth.idle_t = 0.0
	var idled := await _until(s, 6.0, func(): return s.atk_style in ["sloth_sniff", "sloth_rise", "sloth_look"], seen)
	check(idled and seen.has("sloth_walk"), "walks on all fours and stops to sniff or rise and look about: %s" % [seen.keys()])
	# a hero comes within sight: it rises, stares, roars, and comes, building into a run
	await _until(s, 6.0, func(): return s.atk_t < 0.0 and s.sloth.queue.is_empty() and s.sloth.move == "", seen)
	var fwd: Vector3 = -s.rig.global_transform.basis.z
	var spot: Vector3 = g.world.free_spot_near(s.global_position + fwd * 11.0, 2.0)
	g.hero.global_position = spot
	g.hero.global_position.y = g.world.height_at(spot.x, spot.z)
	var noticed := {}
	var roared := await _until(s, 9.0, func(): return noticed.has("sloth_roar") and s.atk_style == "sloth_drop", noticed)
	check(roared and noticed.has("sloth_roar") and (noticed.has("sloth_stare") or noticed.has("sloth_rise")), "it sees the hero: %s" % [noticed.keys()])
	var top := 0.0
	var ran := {}
	var t0 := Time.get_ticks_msec()
	g.hero.global_position = s.global_position + (g.hero.global_position - s.global_position).normalized() * 30.0
	g.hero.global_position = g.world.free_spot_near(g.hero.global_position, 3.0)
	# its speed over half-second spans
	var last: Vector3 = s.global_position
	var lt := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await process_frame
		ran[s.atk_style] = true
		if Time.get_ticks_msec() - lt >= 500:
			var d: float = Vector2(s.global_position.x - last.x, s.global_position.z - last.z).length() / ((Time.get_ticks_msec() - lt) / 1000.0)
			if s.atk_t < 0.0:
				top = maxf(top, d)
			last = s.global_position
			lt = Time.get_ticks_msec()
	check(ran.has("sloth_run") and top > 4.5 and top < 7.2, "it comes on in a lumbering run (top %.1f m/s; the hero walks 4.8, sprints 7.7)" % top)
	# its three skills, with the hero close
	var skills := {}
	var shoved := 0.0
	var dazed := false
	g.test_immortal = false
	g.hero.max_life = 100000.0
	g.hero.life = 100000.0
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 40000 and skills.size() < 3:
		await process_frame
		if not is_instance_valid(s) or s.dead:
			break
		g.hero.life = 100000.0
		# a skill counts once it has landed
		if s.atk_style in ["sloth_sweep", "sloth_slam", "sloth_pounce"] and s.atk_t >= 0.0 and s.impact_done:
			skills[s.atk_style] = true
		shoved = maxf(shoved, g.hero.shove.length())
		dazed = dazed or g.hero.daze_t > 0.0
		var d: float = g.hero.global_position.distance_to(s.global_position)
		# stand close for the sweep and the slam; back off now and then to draw the pounce
		var want := 2.6 if not skills.has("sloth_sweep") or not skills.has("sloth_slam") else 8.0
		if absf(d - want) > 1.5 and s.atk_t < 0.0:
			var away: Vector3 = (g.hero.global_position - s.global_position)
			away.y = 0
			var p: Vector3 = s.global_position + away.normalized() * want
			g.hero.global_position = Vector3(p.x, g.world.height_at(p.x, p.z), p.z)
	check(skills.size() == 3, "its three skills: %s" % [skills.keys()])
	check(shoved > 5.0 and dazed, "the sweep throws the hero back (%.1f m/s) and the slam stuns (%s)" % [shoved, dazed])
	g.test_immortal = true
	# badly hurt it runs off, and comes back
	s.life = s.max_life * 0.45
	s.atk_t = -1.0
	s.sloth.move = ""
	s.sloth.queue.clear()
	var fled := await _until(s, 3.0, func(): return s.sloth.state == "flee", {})
	var d0: float = s.global_position.distance_to(g.hero.global_position)
	await wait(3.0)
	var d1: float = s.global_position.distance_to(g.hero.global_position)
	check(fled and d1 > d0 + 6.0, "at half life it runs (%.0f m -> %.0f m away)" % [d0, d1])
	# the corner map marks it when near
	var mark_ok: bool = g.get_tree().get_nodes_in_group("sloth").size() == 3
	check(mark_ok, "the sloths are listed for the corner map's red marks")
	# get away: out of sight and far, it gives up and roams again
	s.sloth.state = "hunt"
	s.sloth.flees = 2
	# the hero sprints off, keeping well ahead of it
	var gave := await _until(s, 16.0, func():
		var aw: Vector3 = g.hero.global_position - s.global_position
		aw.y = 0
		if aw.length() < 40.0:
			var fp: Vector3 = g.world.free_spot_near(s.global_position + aw.normalized() * 45.0, 4.0)
			g.hero.global_position = Vector3(fp.x, g.world.height_at(fp.x, fp.z), fp.z)
		return s.sloth.state == "roam", {})
	check(gave and not s.aggro, "a hero who gets away is given up on (state %s)" % s.sloth.state)
	# each element's slam, with the hero beside it
	g.test_immortal = false
	for e in ss:
		if not is_instance_valid(e) or e.dead:
			continue
		e.set_process(false)
		var near: Vector3 = e.global_position - e.rig.global_transform.basis.z * 1.8
		g.hero.global_position = Vector3(near.x, g.world.height_at(near.x, near.z), near.z)
		g.hero.max_life = 100000.0
		g.hero.life = 100000.0
		g.hero.daze_t = 0.0
		g.hero.chill_t = 0.0
		var l0: float = g.hero.life
		e.sloth.move = "sloth_slam"
		e.sloth._land(g.hero, 1.8)
		var what := ""
		match e.def["element"]:
			"fire":
				var burn0: float = g.hero.life
				for k in 30:
					e.sloth._tick_hazards(0.05)
					await process_frame
				what = "a ring of fire (%d patches) that burns: %s" % [e.sloth.hazards.size(), g.hero.life < burn0]
				check(e.sloth.hazards.size() > 0 and g.hero.life < burn0, "Cinderhide's slam: " + what)
			"cold":
				what = "frozen %.1f s, chilled %.1f s" % [g.hero.daze_t, g.hero.chill_t]
				check(g.hero.daze_t > 1.5 and g.hero.chill_t > 3.0, "Rimeclaw's slam: " + what)
			"lightning":
				var n: int = e.sloth.strikes.size()
				var lb: float = g.hero.life
				for k in 50:
					e.sloth._tick_hazards(0.05)
					await process_frame
				what = "%d bolts called down, struck: %s" % [n, g.hero.life < lb]
				check(n >= 6 and e.sloth.strikes.is_empty() and g.hero.life < lb, "Thundermaw's slam: " + what)
		e.set_process(true)
	g.test_immortal = true
	g.hero.daze_t = 0.0
	g.hero.chill_t = 0.0
	# and killed: a unique and a heap of gold
	var before: int = g.world.items_root.get_child_count()
	s.take_damage(9999999.0, 0.0, g.hero.global_position, 0.0, false)
	await wait(1.5)
	var drops: Array = g.world.items_root.get_children().slice(before)
	var uniq := drops.filter(func(it): return int(it.item.get("rarity", 0)) >= 3)
	check(drops.size() >= 4 and uniq.size() >= 1, "killed: %d drops, %d unique" % [drops.size(), uniq.size()])
	var mats := drops.filter(func(it): return Items.is_material(it.item))
	check(mats.size() == 1 and mats[0].item["base"] == s.def["drop"], "it drops its own material: %s" % [mats.map(func(it): return it.item["name"])])
	if mats.size() == 1:
		var gi = mats[0]
		check(gi.label.visible and gi._light != null, "it glows on the ground, its name showing")
		var free_before: int = g.hero.inventory.count(null)
		var tings: int = int(get_root().get_node("Sfx").counts.get("relic_ting", 0))
		g._pickup(gi)
		await process_frame
		var held: Array = g.hero.inventory.filter(func(it): return it != null and it["base"] == s.def["drop"])
		check(held.size() == 1 and g.hero.inventory.count(null) == free_before - 1 and int(get_root().get_node("Sfx").counts.get("relic_ting", 0)) > tings,
			"picked up: one inventory space, with the ting (%d)" % (int(get_root().get_node("Sfx").counts.get("relic_ting", 0)) - tings))
		var tex = g.ui.icons.get_icon(held[0], func(_t): pass)
		check(tex != null and tex.get_width() == 256, "its painted icon")
		var tip: Array = Items.tooltip(held[0], 1, "inv")
		check(tip.any(func(l): return str(l[0]) == "Crafting Material"), "tooltip: %s" % [tip.map(func(l): return l[0])])
	print("[S] done, %d failed" % fails)
	quit()
