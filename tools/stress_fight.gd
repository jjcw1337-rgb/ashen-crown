extends SceneTree
## A heavy fight for the frame-time audit (Blaine, 2026-11-05: "the demon and plague doctor fighting or archer ...
## all 3 and plague doctor throwing the bombs ... lots of demon spells at once caused lag"): on the moor, a pack of
## monsters round the hero; the hero (a class) casts every skill in turn at them, and two co-op partners' puppets of
## other classes play their whole recorded skill sets beside him (SkillWarmData's events, as a partner's game would).
## Prints frame-time stats, the worst frames with what had just been cast, and the renderer's counts. With
## `--fx-timing` the slow calls print too (FxTiming). Needs a display.
##   godot --path . -s tools/_late.gd -- res://tools/stress_fight.gd [hero plague] [partners demon,archer] [secs 25] [foes 18] -- --fx-timing

var g
var frames: Array = []
var label := "boot"
var _last := 0
var vp: RID

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_last = Time.get_ticks_usec()
	vp = get_root().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_run()

func _process(_d: float) -> bool:
	var now := Time.get_ticks_usec()
	# [t, dt, what was cast, script process ms, render cpu ms, gpu ms, the slow timed calls]
	frames.append([now / 1000.0, (now - _last) / 1000.0, label, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(),
		RenderingServer.viewport_get_measured_render_time_gpu(vp), FxTiming.calls.duplicate()])
	FxTiming.calls.clear()
	label = ""
	_last = now
	return false

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var cls: String = a[1] if a.size() > 1 and not a[1].begins_with("--") else "plague"
	var partners: PackedStringArray = (a[2] if a.size() > 2 and not a[2].begins_with("--") else "demon,archer").split(",", false)
	if partners.has("-"):
		partners = PackedStringArray()       # "-": no partners
	var idle := a.has("--idle")              # nobody casts: the zone and the monsters alone
	var secs: float = float(a[3]) if a.size() > 3 and not a[3].begins_with("--") else 25.0
	var nfoes: int = int(a[4]) if a.size() > 4 and not a[4].begins_with("--") else 18
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	while g._busy:
		await process_frame
	await g.load_zone(0, "wild", "waypoint")
	while g._busy:
		await process_frame
	g.test_immortal = true
	g.test_allskills = true
	if a.has("--q"):
		g.apply_quality(int(a[a.find("--q") + 1]))     # a preset for this run only (not saved)
	print("[S] preset %s at %s" % [g.QUALITY_NAMES[g.quality], str(get_root().get_visible_rect().size)])
	var h: Hero = g.hero
	var c: Vector3 = h.global_position
	# the partners' puppets, and their classes' warmed effects (as a partner's game warms its own)
	var pups: Array = []
	for i in partners.size():
		var p := Hero.new()
		p.puppet = true
		p.peer_id = 90 + i
		p.name = "Partner_" + partners[i]
		g.add_child(p)
		p.setup(g)
		p.set_class(partners[i])
		var at := c + Vector3(-3.0 + 6.0 * i, 0, 1.5)
		p.global_position = at
		p.net_pos = at
		p.net_st = {"move": 0.0, "atk": -1.0, "style": "over", "block": 0.0, "hit": 0.0}
		p.net_has = true
		pups.append(p)
	# as a zone change with the party in it: their classes warmed under the loading screen (SkillWarm.run)
	if not a.has("--nowarm"):
		await SkillWarm.run(g, [cls] + Array(partners))   # (these puppets aren't in Net.players)
	var foes: Array = []
	for i in nfoes:
		var ang := TAU * i / maxi(1, nfoes)
		var e = g.spawn_enemy("zombie" if i % 2 == 0 else "fallen_skirmisher", c + Vector3(cos(ang), 0, sin(ang)) * randf_range(4.0, 8.0), 1)
		if e != null:
			e.max_life = 99999.0
			e.life = 99999.0
			foes.append(e)
	await create_timer(1.0).timeout
	var ids: Array = Data.skills_for(cls).map(func(s): return s["id"])
	var evs := {}
	for pc in partners:
		evs[pc] = SkillWarmData.EVENTS.get(pc, [])
	var i0 := frames.size()
	var t0 := Time.get_ticks_msec()
	var next_cast := 0.0
	var next_pup := 0.0
	var k := 0
	var kp := 0
	var max_lights := 0
	var max_shadowed := 0
	var max_parts := 0
	var max_draws := 0
	var max_objs := 0
	while Time.get_ticks_msec() - t0 < int(secs * 1000.0):
		await process_frame
		var now := (Time.get_ticks_msec() - t0) / 1000.0
		max_draws = maxi(max_draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		max_objs = maxi(max_objs, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
		if Engine.get_process_frames() % 30 == 0:
			var nl := 0
			var ns := 0
			var np := 0
			for x in g.world.find_children("*", "", true, false):
				if x is OmniLight3D or x is SpotLight3D:
					if (x as Light3D).is_visible_in_tree() and (x as Light3D).light_energy > 0.01:
						nl += 1
						if (x as Light3D).shadow_enabled:
							ns += 1
				elif x is GPUParticles3D and (x as GPUParticles3D).emitting:
					np += (x as GPUParticles3D).amount
			max_lights = maxi(max_lights, nl)
			max_shadowed = maxi(max_shadowed, ns)
			max_parts = maxi(max_parts, np)
		if now >= next_cast and not idle:
			next_cast = now + 0.7
			h.mana = 9999.0
			for key in h.cds.keys():
				h.cds[key] = 0.0
			var tgt: Vector3 = c + Vector3(0, 0, -5)
			if not foes.is_empty() and is_instance_valid(foes[k % maxi(1, foes.size())]):
				tgt = (foes[k % foes.size()] as Node3D).global_position
			var id: String = str(ids[k % ids.size()]) if k % 3 != 2 else "attack"
			label += "hero " + id + "; "
			if id == "attack":
				h.swipe_attack(tgt)
			else:
				h.use_skill(id, tgt)
			k += 1
		if now >= next_pup and not idle:
			next_pup = now + 0.35
			for pi in pups.size():
				var pcls: String = partners[pi]
				var list: Array = evs[pcls]
				if list.is_empty():
					continue
				var w = list[kp % list.size()]
				if w is Dictionary:
					label += "%s %s/%s; " % [pcls, w.get("s", ""), w.get("e", "")]
					SkillFx.play(pups[pi], SkillWarm._rebuild(w, (pups[pi] as Node3D).global_position))
			kp += 1
	label = "end"
	var fs := frames.slice(i0)
	var dts: Array = fs.map(func(f): return float(f[1]))
	dts.sort()
	var n := dts.size()
	var tot := 0.0
	for d in dts:
		tot += d
	print("[S] %s with %s, %d foes, %.0f s: %d frames, mean %.1f ms (%.0f fps), p50 %.1f, p95 %.1f, p99 %.1f, worst %.1f; over 33 ms %d, over 50 ms %d, over 100 ms %d; draw calls up to %d, objects up to %d" % [
		cls, ",".join(partners), foes.size(), secs, n, tot / n, 1000.0 / (tot / n), dts[n / 2], dts[int(n * 0.95)], dts[mini(n - 1, int(n * 0.99))], dts[n - 1],
		dts.filter(func(d): return d > 33.0).size(), dts.filter(func(d): return d > 50.0).size(), dts.filter(func(d): return d > 100.0).size(), max_draws, max_objs])
	var worst := fs.duplicate()
	worst.sort_custom(func(x, y): return x[1] > y[1])
	for i in mini(14, worst.size()):
		var f: Array = worst[i]
		var j := fs.find(f)
		var prev: Array = fs[j - 1] if j > 0 else f
		var nxt: Array = fs[j + 1] if j + 1 < fs.size() else f
		var cs: Array = (f[6] as Array).map(func(c): return "%s %.0f" % [c[0], c[1]])
		print("[S]    %.0f ms at %.1f s: cast %s| process %.0f/%.0f, render cpu %.0f/%.0f, gpu %.0f/%.0f | %s" % [f[1], (f[0] - fs[0][0]) / 1000.0,
			str(prev[2]) + str(f[2]), f[3], nxt[3], f[4], nxt[4], f[5], nxt[5], ", ".join(cs)])
	var pt: Array = fs.map(func(f): return float(f[3]))
	pt.sort()
	var gt: Array = fs.map(func(f): return float(f[5]))
	gt.sort()
	print("[S] script process p50 %.1f ms p95 %.1f; gpu p50 %.1f p95 %.1f" % [pt[n / 2], pt[int(n * 0.95)], gt[n / 2], gt[int(n * 0.95)]])
	print("[S] lights up to %d (%d with shadows), emitting particles up to %d" % [max_lights, max_shadowed, max_parts])
	print("[S] fx nodes alive at the end: %d" % g.world.fx_root.get_child_count())
	quit()
