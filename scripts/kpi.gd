class_name Kpi
## The official performance KPIs (docs/systems/performance_kpis.md): fixed, scripted scenarios measured the same way every time,
## in any build (an exported game too):
##   AshenCrown -- --kpi <scenario> <out.json> [--quality 0-3] [--secs N] [--class C] [--skill id|none] [--trace]
##   (--class: the hero (default knight); --skill: cast only that skill (none: only the weapon); --trace: the JSON
##   also lists every frame's time and when each cast went off, to line stutters up with what caused them)
##   godot --headless --path . -- --server --kpi server <out.json>       (the dedicated server's tick)
## Scenarios (`SCENARIOS`): camp, moor, fight, boss, arena, crypt, server. Each loads its zone (timed: load_ms), stages
## the scene (the hero immortal), settles `SETTLE` s (shaders compile, AI wakes), then drives it for `secs` measuring
## every frame, and writes one JSON object of metrics (see `_finish`) plus a screenshot next to it; then quits.
## Deterministic: fixed seeds, fixed paths, fixed spawns.

const SETTLE := 4.0
const SCENARIOS := {
	# zone, run, secs, what it is
	"camp": {"zone": "town", "run": 0, "secs": 15.0, "what": "Act I camp: walking a loop past the tents, the fire and the traders"},
	"moor": {"zone": "wild", "run": 0, "secs": 20.0, "what": "Act I moor: running up the road, grass, trees and the world streaming in"},
	"fight": {"zone": "wild", "run": 0, "secs": 20.0, "what": "Act I moor: the knight fighting 24 monsters at once with every skill (kills replaced)"},
	"boss": {"zone": "lair", "run": 0, "secs": 25.0, "what": "Grubb's fort: the King Grubb fight, the knight on him with skills"},
	"arena": {"zone": "lair", "run": 1, "secs": 25.0, "what": "A2 Aurelia: the arena games (lions, the crowd) with the knight on the sand"},
	"crypt": {"zone": "bg", "run": 0, "secs": 20.0, "what": "Battlegrounds (the Verdant Reach; the id is kept for history): walking and fighting what's there"},
	"server": {"zone": "bg", "run": 0, "secs": 30.0, "what": "The dedicated Battlegrounds server (headless): its frame time with the crypt running"},
	# a place a player reported as slow (tools/telemetry_query.sh spots): --zone Z --run R --pos x,z [--foes N]
	"spot": {"zone": "wild", "run": 0, "secs": 15.0, "what": "Any place: the hero standing at --pos in --zone (--run), turning, --foes N monsters about"},
}
const FIGHT_FOES := 24
const HITCH_MS := 100.0          # a frame this long is a visible stutter

static var g
static var sc := ""
static var out := ""
static var st := {}

## From Game._ready when the command line has --kpi. Returns false if there's no --kpi.
static func start(game) -> bool:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--kpi")
	if i < 0 or i + 1 >= a.size():
		return false
	g = game
	sc = a[i + 1]
	out = a[i + 2] if i + 2 < a.size() and not a[i + 2].begins_with("--") else "user://kpi_%s.json" % sc
	if not SCENARIOS.has(sc):
		printerr("[KPI] unknown scenario ", sc, "; one of ", SCENARIOS.keys())
		g.get_tree().quit(2)
		return true
	var spec: Dictionary = (SCENARIOS[sc] as Dictionary).duplicate()
	if sc == "spot":
		var zi := a.find("--zone")
		var ri := a.find("--run")
		if zi >= 0 and zi + 1 < a.size():
			spec["zone"] = a[zi + 1]
		if ri >= 0 and ri + 1 < a.size():
			spec["run"] = int(a[ri + 1])
	var secs: float = spec["secs"]
	var si := a.find("--secs")
	if si >= 0 and si + 1 < a.size():
		secs = float(a[si + 1])
	st = {"secs": secs, "phase": "load", "t": 0.0, "frames": [], "proc": 0.0, "phys": 0.0,
		"dc": 0.0, "prims": 0.0, "objs": 0.0, "gpu": 0.0, "n": 0, "next_skill": 0.0, "path_i": -1, "boot_ms": Time.get_ticks_msec()}
	for k in 2:
		var pr: Node = load("res://scripts/kpi_probe.gd").new()
		pr.first = k == 0
		pr.process_priority = -100000 if k == 0 else 100000
		pr.process_physics_priority = -100000 if k == 0 else 100000
		pr.name = "KpiProbe%d" % k
		g.add_child.call_deferred(pr)
	if sc == "server":
		return false      # the server starts as usual; `server_tick` measures it
	var qi := a.find("--quality")
	g.set_quality(int(a[qi + 1]) if qi >= 0 and qi + 1 < a.size() else 2)
	g.ui.hide_title()
	g.playing = true
	g.difficulty = int(spec["run"])
	var ci := a.find("--class")
	g.hero.set_class(a[ci + 1] if ci >= 0 and ci + 1 < a.size() else "knight")
	var ki := a.find("--skill")
	st["skill"] = a[ki + 1] if ki >= 0 and ki + 1 < a.size() else ""
	st["trace"] = a.has("--trace")
	st["casts"] = []
	g.hero.new_character()
	g.hero.set_level(20)
	g.test_immortal = true
	_load.call_deferred(spec)
	return true

static func _load(spec: Dictionary) -> void:
	var t0 := Time.get_ticks_msec()
	await g.load_zone(0, spec["zone"], "start")
	st["load_ms"] = Time.get_ticks_msec() - t0
	_stage()
	_hide_parts()
	_no_shadows()
	_env_off()
	_mm_no_shadow()
	_no_cast()
	st["phase"] = "settle"
	RenderingServer.viewport_set_measure_render_time(g.get_viewport().get_viewport_rid(), true)

## Called every frame by Game._process (and by the server's loop through `server_tick`).
static func step(delta: float) -> void:
	if st.is_empty() or st["phase"] in ["load", "done"] or g._busy:
		return
	st["t"] = float(st["t"]) + delta
	_drive(delta)
	if st["phase"] == "settle":
		if float(st["t"]) >= SETTLE:
			st["phase"] = "measure"
			st["t"] = 0.0
			# the profiling switches again, now the zone has settled: what the settle built or re-enabled (deferred
			# multimesh cells, apply_quality, Grade's shadow picks) is caught too (nightly 2026-11-05)
			_hide_parts()
			_no_shadows()
			_env_off()
			_mm_no_shadow()
			_no_cast()
			st["t0"] = Time.get_ticks_usec()
			st["p0"] = [load("res://scripts/kpi_probe.gd").proc_us, load("res://scripts/kpi_probe.gd").phys_us]
			if OS.get_cmdline_user_args().has("--census"):
				_census()
		return
	(st["frames"] as Array).append(delta * 1000.0)
	st["proc"] = float(st["proc"]) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	st["phys"] = float(st["phys"]) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	st["dc"] = float(st["dc"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	st["prims"] = float(st["prims"]) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	st["objs"] = float(st["objs"]) + Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	if sc != "server":
		st["gpu"] = float(st["gpu"]) + RenderingServer.viewport_get_measured_render_time_gpu(g.get_viewport().get_viewport_rid())
		st["rcpu"] = float(st.get("rcpu", 0.0)) + RenderingServer.viewport_get_measured_render_time_cpu(g.get_viewport().get_viewport_rid()) + RenderingServer.get_frame_setup_time_cpu()
	st["n"] = int(st["n"]) + 1
	if float(st["t"]) >= float(st["secs"]):
		_finish()

## The dedicated server: measuring starts once its zone is up.
static func server_tick(delta: float) -> void:
	if sc != "server" or st.is_empty():
		return
	if st["phase"] == "load":
		if g.world != null and not g._busy and g.cur_zone == Battlegrounds.ZONE:
			st["load_ms"] = Time.get_ticks_msec() - int(st["boot_ms"])
			st["phase"] = "settle"
			st["t"] = 0.0
		return
	step(delta)

# ---------------------------------------------------------------- the scenes

static func _stage() -> void:
	var h = g.hero
	match sc:
		"fight":
			var r := RandomNumberGenerator.new()
			r.seed = 9
			h.global_position = g.world.free_spot_near(h.global_position + Vector3(14, 0, 0), 1.0)
			for i in FIGHT_FOES:
				_spawn_foe(r, i)
		"boss":
			for e in g.enemies_near(h.global_position, 400.0):
				if e.boss:
					st["boss"] = e
					e.aggro = true
					h.global_position = g.world.free_spot_near(e.global_position + Vector3(0, 0, 3.0), 0.5)
					break
		"spot":
			var a := OS.get_cmdline_user_args()
			var pi := a.find("--pos")
			if pi >= 0 and pi + 1 < a.size() and a[pi + 1].begins_with("oak"):
				# --pos oakN: beside the Nth oak that casts its shadow from a twin (comparing tree shadows)
				var want := int(a[pi + 1].substr(3))
				var k := 0
				for mi in g.world.find_children("*", "MultiMeshInstance3D", true, false):
					if mi.has_meta("shadow_twin") and mi.multimesh.instance_count > 0:
						if k == want:
							var o: Vector3 = mi.multimesh.get_instance_transform(0).origin
							h.global_position = g.world.free_spot_near(o + Vector3(3.5, 0, 3.5), 1.0)
							print("[KPI] spot at ", h.global_position)
							break
						k += 1
			elif pi >= 0 and pi + 1 < a.size():
				var xz := a[pi + 1].split(",")
				h.global_position = g.world.free_spot_near(Vector3(float(xz[0]), 0, float(xz[1])), 0.5)
			var fi := a.find("--foes")
			var r := RandomNumberGenerator.new()
			r.seed = 9
			for i in (int(a[fi + 1]) if fi >= 0 and fi + 1 < a.size() else 0):
				_spawn_foe(r, i)
		"arena":
			if g.world.has_meta("games"):
				g.world.get_meta("games").begin()
			var c: Vector2 = Aurelia.CENTRE
			h.global_position = g.world.free_spot_near(Vector3(c.x, 0, c.y), 0.5)
	g.cam_target = h.global_position

static func _spawn_foe(r: RandomNumberGenerator, i: int) -> void:
	var foes: Array = Data.act_info(0, 0).get("foes", ["zombie"])
	var a := TAU * i / FIGHT_FOES + r.randf() * 0.2
	var p: Vector3 = g.hero.global_position + Vector3(cos(a), 0, sin(a)) * r.randf_range(5.0, 10.0)
	var e = g.spawn_enemy(str(foes[i % foes.size()]), g.world.free_spot_near(p, 0.6), 8)
	if e:
		e.aggro = true

static func _drive(delta: float) -> void:
	var h = g.hero
	h.life = h.max_life
	match sc:
		"camp":
			var a := float(st["t"]) * 0.5
			var c: Vector3 = st.get("centre", h.global_position)
			st["centre"] = c
			h.global_position = g.world.move(h.global_position, (c + Vector3(cos(a), 0, sin(a)) * 7.0 - h.global_position).limit_length(5.0 * delta))
		"moor":
			_run_road(delta, 7.0)
		"spot":
			h.rig.rotation.y = float(st["t"]) * 0.6      # (looking all round the place)
		"fight", "boss", "arena", "crypt":
			if sc == "crypt":
				_run_road(delta, 3.5)
			var foes: Array = g.enemies_near(h.global_position, 30.0).filter(func(e): return not e.dead)
			if sc == "fight" and foes.size() < FIGHT_FOES:
				var r := RandomNumberGenerator.new()
				r.seed = int(st["n"])
				_spawn_foe(r, int(st["n"]) % FIGHT_FOES)
			if foes.is_empty():
				return
			var tgt = st.get("boss", null) if is_instance_valid(st.get("boss", null)) else foes[0]
			if h.target != tgt and h.atk_t < 0.0:
				h.cmd_target(tgt)
			if float(st["t"]) >= float(st["next_skill"]):
				st["next_skill"] = float(st["t"]) + 1.2
				h.mana = h.max_mana          # (what's measured is the frame, not the mana)
				if str(st["skill"]) != "":
					h.cds[str(st["skill"])] = 0.0      # (a long cooldown, an ultimate's, would leave the window with no cast)
				if str(st["skill"]) != "" and h.run == null and Data.run_skills_for(h.cls).any(func(x): return x["id"] == str(st["skill"])):
					# a run's skill (Data.RUN_SKILLS): only a run character has it
					h.run = RunBuild.new()
					h.run.skills.append(str(st["skill"]))
				for s in h.skill_list() + (Data.shared_skills() if str(st["skill"]) != "" else []):
					if str(st["skill"]) != "" and str(s["id"]) != str(st["skill"]):
						continue
					if h.use_skill(str(s["id"]), tgt.global_position):
						if st["phase"] == "measure":
							(st["casts"] as Array).append([str(s["id"]), (st["frames"] as Array).size()])
						break
	g.cam_target = h.global_position

## Along the zone's road (World.path_poly), or a wide loop where there's none (the crypt).
static func _run_road(delta: float, speed: float) -> void:
	var h = g.hero
	var pp: PackedVector2Array = g.world.path_poly
	if pp.size() < 2:
		var a := float(st["t"]) * speed / 9.0
		var c: Vector3 = st.get("centre", h.global_position)
		st["centre"] = c
		h.global_position = g.world.move(h.global_position, (c + Vector3(cos(a), 0, sin(a)) * 9.0 - h.global_position).limit_length(speed * delta))
		return
	var i: int = st["path_i"]
	if i < 0:
		var best := INF
		for k in pp.size():
			var d := pp[k].distance_to(Vector2(h.global_position.x, h.global_position.z))
			if d < best:
				best = d
				i = k
	var goal := pp[mini(i + 1, pp.size() - 1)]
	var p2 := Vector2(h.global_position.x, h.global_position.z)
	if p2.distance_to(goal) < 1.5:
		i = mini(i + 1, pp.size() - 2)
	st["path_i"] = i
	var d2 := (goal - p2).limit_length(speed * delta)
	var np := Vector3(p2.x + d2.x, 0, p2.y + d2.y)
	np.y = g.world.height_at(np.x, np.z)
	if d2.length() > 0.001:
		h.rig.rotation.y = atan2(-d2.x, -d2.y)
	h.global_position = np

# ---------------------------------------------------------------- the census (a profiling aid)

## --census: what the frame is made of, written next to out.json as .census.txt: every visible mesh (grouped by
## its mesh) with its triangles, instances, shadow casting and visibility range, and every light with shadows.
## --hide a,b,c: hides every node whose name contains one of them (to measure what a part costs).
static func _census() -> void:
	var rows := {}
	var lights: Array = []
	var cam: Camera3D = g.get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam else Vector3.ZERO
	var stack: Array = [g.get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Light3D:
			var l: Light3D = n
			if l.is_visible_in_tree():
				lights.append("%s %s shadow=%s range=%.1f dist=%.1f path=%s" % [l.get_class(), l.name, l.shadow_enabled,
					l.get("omni_range") if l is OmniLight3D else (l.get("spot_range") if l is SpotLight3D else 0.0),
					l.global_position.distance_to(cp), str(l.get_path()).right(90)])
			continue
		if not (n is GeometryInstance3D) or not (n as Node3D).is_visible_in_tree():
			continue
		var mesh: Mesh = null
		var inst := 1
		if n is MeshInstance3D:
			mesh = (n as MeshInstance3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			inst = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		elif n is GPUParticles3D:
			mesh = (n as GPUParticles3D).draw_pass_1
			inst = (n as GPUParticles3D).amount
		elif n is CPUParticles3D:
			mesh = (n as CPUParticles3D).mesh
			inst = (n as CPUParticles3D).amount
		if mesh == null:
			continue
		var tris := 0
		if mesh is PrimitiveMesh:
			var arr: Array = (mesh as PrimitiveMesh).get_mesh_arrays()
			tris = ((arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arr[Mesh.ARRAY_INDEX] != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		if mesh is ArrayMesh:
			for si in mesh.get_surface_count():
				var il: int = (mesh as ArrayMesh).surface_get_array_index_len(si)
				tris += (il if il > 0 else (mesh as ArrayMesh).surface_get_array_len(si)) / 3
		var gi: GeometryInstance3D = n
		var key := "%s|%s" % [mesh.resource_path if mesh.resource_path != "" else str(n.name).rstrip("0123456789@"), str(tris)]
		var r: Dictionary = rows.get(key, {"tris": tris, "n": 0, "inst": 0, "shadow": 0, "vis": 0, "near": 1e9, "path": str(n.get_path()).right(100)})
		r["n"] = int(r["n"]) + 1
		r["inst"] = int(r["inst"]) + inst
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			r["shadow"] = int(r["shadow"]) + inst
		if gi.visibility_range_end > 0.0:
			r["vis"] = int(r["vis"]) + 1
		r["near"] = minf(float(r["near"]), (gi as Node3D).global_position.distance_to(cp))
		rows[key] = r
	var keys: Array = rows.keys()
	keys.sort_custom(func(a, b): return int(rows[a]["tris"]) * int(rows[a]["inst"]) > int(rows[b]["tris"]) * int(rows[b]["inst"]))
	var lines: PackedStringArray = ["total_tris instances shadow_inst vis_ranged nearest_m tris_each  key  path"]
	var total := 0
	for k in keys:
		var r: Dictionary = rows[k]
		total += int(r["tris"]) * int(r["inst"])
	lines.append("TOTAL %d" % total)
	for k in keys.slice(0, 120):
		var r: Dictionary = rows[k]
		lines.append("%10d %6d %6d %4d %6.1f %8d  %s  %s" % [int(r["tris"]) * int(r["inst"]), int(r["inst"]), int(r["shadow"]), int(r["vis"]), float(r["near"]), int(r["tris"]), k, r["path"]])
	lines.append("")
	for v in g.get_tree().root.find_children("*", "SubViewport", true, false):
		var sv: SubViewport = v
		lines.append("VIEWPORT %s size=%s update=%d own_world=%s world=%s disable3d=%s" % [str(sv.get_path()).right(110), str(sv.size), sv.render_target_update_mode, sv.own_world_3d, str(sv.find_world_3d()), sv.disable_3d])
	lines.append("MAIN world=%s" % str(g.get_viewport().find_world_3d()))
	lines.append("LIGHTS %d" % lights.size())
	lines.append_array(PackedStringArray(lights))
	var f := FileAccess.open(out.get_basename() + ".census.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()

static func _hide_parts() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--hide")
	if i < 0 or i + 1 >= a.size():
		return
	var pats := a[i + 1].split(",")
	if pats[0].contains("#"):      # Props#10-20: children 10..20 of the world's node named Props
		var pr := pats[0].split("#")
		var par: Node = g.world.find_child(pr[0], true, false)
		var ab := pr[1].split("-")
		var kids := par.get_children()
		for ci in range(int(ab[0]), mini(int(ab[1]) + 1, kids.size())):
			if kids[ci] is Node3D:
				(kids[ci] as Node3D).visible = false
				var ms: Array = []
				for m in kids[ci].find_children("*", "GeometryInstance3D", true, false):
					var mm = m.get("mesh") if m is MeshInstance3D else (m.multimesh.mesh if m is MultiMeshInstance3D and m.multimesh else null)
					ms.append("%s:%s:%s:%s" % [m.name, m.get_class(), mm.resource_path.get_file() if mm else "", (m.multimesh.instance_count if m is MultiMeshInstance3D and m.multimesh else 1)])
				if kids[ci] is MultiMeshInstance3D and kids[ci].multimesh and kids[ci].multimesh.mesh:
					var mmm: Mesh = kids[ci].multimesh.mesh
					var info: Array = []
					for si in mmm.get_surface_count():
						info.append([mmm.surface_get_array_index_len(si) if mmm is ArrayMesh else -1, mmm.surface_get_array_len(si) if mmm is ArrayMesh else -1])
					ms.append("MM %s %s inst=%d vis=%d surf=%s lods=%s cs=%d aabb=%s mat=%s" % [mmm.get_class(), mmm.resource_path, kids[ci].multimesh.instance_count, kids[ci].multimesh.visible_instance_count, str(info), str(RenderingServer.mesh_get_surface_count(mmm.get_rid())), kids[ci].cast_shadow, str(kids[ci].get_aabb().size), str(kids[ci].material_override)])
				print("[KPI]  ", ci, " ", kids[ci].name, " ", kids[ci].get_class(), " ", (kids[ci] as Node3D).global_position, " ", ms.slice(0, 6))
		print("[KPI] hid ", pr, " of ", kids.size())
		return
	var stack: Array = [g.world]
	var hidden := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var hit := false
		for p in pats:
			if p != "" and str(n.name).contains(p):
				hit = true
		if hit and n is Node3D:
			(n as Node3D).visible = false
			hidden += 1
			continue
		for c in n.get_children():
			stack.append(c)
	print("[KPI] hid ", hidden, " nodes matching ", pats)

## --envoff ssao,ssil,vfog,msaa,glow,fog,sdfgi,ssr,msaa4,grass...: (profiling) turns those off. A later apply_quality can
## turn them back on (sdfgi in --fixed-fps runs, 2026-11-03): check gpu_ms moved before trusting a comparison.
static func _env_off() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--envoff")
	if i < 0 or i + 1 >= a.size():
		return
	var k := a[i + 1]
	var env: Environment = g.env
	if k.contains("ssao"): env.ssao_enabled = false
	if k.contains("aoon"): env.ssao_enabled = true
	if k.contains("ssil"): env.ssil_enabled = false
	if k.contains("sdfgi"): env.sdfgi_enabled = false
	if k.contains("ssr"): env.ssr_enabled = false
	if k.contains("msaa4"): g.get_viewport().msaa_3d = Viewport.MSAA_4X
	if k.contains("vfog"): env.volumetric_fog_enabled = false
	if k.contains("glow"): env.glow_enabled = false
	if k.contains("dfog"): env.fog_enabled = false
	if k.contains("msaa") and not k.contains("msaa4"): g.get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	if k.contains("half"): g.get_viewport().scaling_3d_scale = 0.5
	if k.contains("softmed"): RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
	if k.contains("softlow"): RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	if k.contains("atlas2k"): RenderingServer.directional_shadow_atlas_set_size(2048, true)
	if k.contains("omnidp"):
		for l in g.world.find_children("*", "OmniLight3D", true, false):
			(l as OmniLight3D).omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	if k.contains("plainomni"):
		for l in g.world.find_children("*", "OmniLight3D", true, false):
			if not (l as Light3D).is_in_group(Grade.SHADOW_GROUP):
				(l as Light3D).visible = false
	if k.contains("grassflatfrag") or k.contains("grassnopatch") or k.contains("grassdegen"):
		for gi in g.get_tree().get_nodes_in_group("grass"):
			var m := (gi as GeometryInstance3D).material_override as ShaderMaterial
			if m and not m.has_meta("kpi_done"):
				var sh: Shader = m.shader
				if not sh.has_meta("kpi_done"):
					if k.contains("grassdegen"):
						sh.code = sh.code.replace("	VERTEX = o + rel;", "	VERTEX = o;")
					elif k.contains("grassnopatch"):
						sh.code = sh.code.replace("float patch = vn(wpos.xz * 0.09 + 3.1) * 0.7 + vn(wpos.xz * 0.7) * 0.3;", "float patch = 0.5;")
					else:
						var fi := sh.code.find("void fragment(){")
						sh.code = sh.code.substr(0, fi) + "void fragment(){ vec4 t = texture(atlas, UV); ALBEDO = vec3(0.2,0.3,0.1) * t.rgb; ALPHA = t.a; ALPHA_SCISSOR_THRESHOLD = 0.5; ALPHA_ANTIALIASING_EDGE = 0.3; }\n"
					sh.set_meta("kpi_done", true)
	if k.contains("grasslod"):        # grasslod<near>: the LOD0 -> LOD1 hand-over band from <near> m (5 m wide)
		var nb := float(k.substr(k.find("grasslod") + 8, 2))
		for ms in Grass._mats.values():
			for m in ms:
				(m as ShaderMaterial).set_shader_parameter("lod_band", Vector2(nb, nb + 5.0))
	if k.contains("terrainnofd"):
		var sh: Shader = Mats.shader("terrain")
		sh.code = sh.code.replace("float hc = fbm3(p * sc); float hx = fbm3((p + vec2(e, 0.0)) * sc); float hz = fbm3((p + vec2(0.0, e)) * sc);", "float hc = 0.5; float hx = 0.5; float hz = 0.5;")
	if k.contains("terrainflat"):
		for t in g.world.find_children("Terrain*", "MeshInstance3D", true, false):
			var sm := StandardMaterial3D.new()
			sm.albedo_color = Color(0.25, 0.28, 0.15)
			(t as MeshInstance3D).material_override = sm

## --mmnoshadow N: (profiling) MultiMeshes whose mesh has more than N triangles cast no shadow.
static func _mm_no_shadow() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--mmnoshadow")
	if i < 0 or i + 1 >= a.size():
		return
	var lim := int(a[i + 1])
	var n := 0
	for mi in g.world.find_children("*", "MultiMeshInstance3D", true, false):
		var m: Mesh = mi.multimesh.mesh if mi.multimesh else null
		if m is ArrayMesh:
			var t := 0
			for si in m.get_surface_count():
				var il: int = m.surface_get_array_index_len(si)
				t += (il if il > 0 else m.surface_get_array_len(si)) / 3
			if t > lim:
				if a.has("--mmhide"):
					mi.visible = false         # --mmhide: hide them altogether (what they cost in every pass)
				else:
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				n += 1
	print("[KPI] shadows off on ", n, " multimeshes")

## --nocast a,b: (profiling) geometry whose node name contains a or b casts no shadow; `--nocast all-mm` = every
## GeometryInstance3D that isn't a MultiMesh. Prints how many and their triangles.
static func _no_cast() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--nocast")
	if i < 0 or i + 1 >= a.size():
		return
	var pats := a[i + 1].split(",")
	var n := 0
	for gi in g.world.find_children("*", "GeometryInstance3D", true, false):
		var hit := false
		for p in pats:
			if p == "all-mm" and not (gi is MultiMeshInstance3D):
				hit = true
			elif p == "cut" and not (gi is MultiMeshInstance3D) and _cutout(gi):
				hit = true        # --nocast cut: every single mesh with a cut-out material (see _cutout)
			elif p != "all-mm" and p != "cut" and str(gi.name).contains(p):
				hit = true
		if hit and (gi as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n += 1
	print("[KPI] nocast ", n, " ", pats)
	if a.has("--castlist"):
		var by := {}
		for gi in g.world.find_children("*", "MeshInstance3D", true, false):
			var mi := gi as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var tris := 0
			for si in mi.mesh.get_surface_count():
				var il: int = (mi.mesh as ArrayMesh).surface_get_array_index_len(si) if mi.mesh is ArrayMesh else 0
				tris += il / 3
			var key := mi.mesh.resource_path.get_file() if mi.mesh.resource_path != "" else str(mi.get_parent().name) + "/" + str(mi.name)
			key += " cast=%d cut=%s" % [mi.cast_shadow, _cutout(mi)]
			if not by.has(key):
				by[key] = [0, 0]
			by[key][0] += tris
			by[key][1] += 1
		var ks := by.keys()
		ks.sort_custom(func(x, y): return int(by[x][0]) > int(by[y][0]))
		for k in ks.slice(0, 40):
			print("[KPI] cast ", by[k][0], " x", by[k][1], " ", k)
		var mmby := {}
		for gi in g.world.find_children("*", "MultiMeshInstance3D", true, false):
			var mi := gi as MultiMeshInstance3D
			if mi.multimesh == null or mi.multimesh.mesh == null or not mi.is_visible_in_tree() or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				continue
			var m: Mesh = mi.multimesh.mesh
			var tris := 0
			for si in m.get_surface_count():
				tris += ((m as ArrayMesh).surface_get_array_index_len(si) if m is ArrayMesh else 0) / 3
			var mat = mi.material_override if mi.material_override else (m.surface_get_material(0) if m.get_surface_count() > 0 else null)
			var key := "%s tris=%d cast=%d twin=%s mat=%s" % [m.resource_path.get_file() if m.resource_path != "" else str(m.get_rid().get_id()), tris, mi.cast_shadow, mi.has_meta("shadow_twin"), (mat.shader.resource_path.get_file() + ":" + str(mat.shader.get_rid().get_id())) if mat is ShaderMaterial else str(mat)]
			if not mmby.has(key):
				mmby[key] = [0, 0]
			mmby[key][0] += tris * mi.multimesh.instance_count
			mmby[key][1] += mi.multimesh.instance_count
		var mk := mmby.keys()
		mk.sort_custom(func(x, y): return int(mmby[x][0]) > int(mmby[y][0]))
		for k in mk.slice(0, 30):
			print("[KPI] mmcast ", mmby[k][0], " x", mmby[k][1], " ", k)

## (castlist) Does the geometry draw any surface with a cut-out material (discard / alpha scissor)? Those pay per
## pixel in every shadow cascade (bake a mask: Flora.shadow_twin).
static func _cutout(gi: GeometryInstance3D) -> bool:
	var mats: Array = [gi.material_override]
	var m: Mesh = (gi as MeshInstance3D).mesh if gi is MeshInstance3D else null
	if m != null:
		for si in m.get_surface_count():
			mats.append((gi as MeshInstance3D).get_active_material(si))
	for mat in mats:
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader != null:
			var c: String = (mat as ShaderMaterial).shader.code
			if c.contains("discard") or c.contains("ALPHA_SCISSOR"):
				return true
		elif mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			return true
	return false

## --noshadow omni,dir: (profiling) turns those lights' shadows off.
static func _no_shadows() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--noshadow")
	if i < 0 or i + 1 >= a.size():
		return
	var kinds := a[i + 1]
	for l in g.find_children("*", "Light3D", true, false):
		if (l is DirectionalLight3D and kinds.contains("dir")) or (not (l is DirectionalLight3D) and kinds.contains("omni")):
			(l as Light3D).shadow_enabled = false
			(l as Light3D).remove_from_group(Grade.SHADOW_GROUP)

# ---------------------------------------------------------------- the numbers

static func _finish() -> void:
	st["phase"] = "done"
	var fr: Array = st["frames"]
	var n := maxi(1, fr.size())
	var wall := float(Time.get_ticks_usec() - int(st["t0"])) / 1e6
	var s := fr.duplicate()
	s.sort()
	var k := maxi(1, int(n * 0.01))
	var worst1 := 0.0
	for i in k:
		worst1 += float(s[n - 1 - i])
	worst1 /= k
	var hitches := 0
	for f in fr:
		if f >= HITCH_MS:
			hitches += 1
	var r := {
		"scenario": sc, "preset": g.quality, "secs": snappedf(wall, 0.01), "frames": n,
		"fps_avg": snappedf(n / wall, 0.1),
		"fps_low1": snappedf(1000.0 / worst1, 0.1),
		"frame_ms_median": snappedf(float(s[n / 2]), 0.01),
		"frame_ms_p99": snappedf(float(s[mini(n - 1, int(n * 0.99))]), 0.01),
		"hitches_per_min": snappedf(hitches * 60.0 / wall, 0.1),
		"cpu_process_peak_ms": snappedf(float(st["proc"]) / n, 0.01),
		"cpu_physics_peak_ms": snappedf(float(st["phys"]) / n, 0.01),
		"gpu_ms": snappedf(float(st["gpu"]) / n, 0.01),
		"script_ms": snappedf(float(load("res://scripts/kpi_probe.gd").proc_us - int((st.get("p0", [0, 0]) as Array)[0])) / 1000.0 / n, 0.01),
		"physics_ms": snappedf(float(load("res://scripts/kpi_probe.gd").phys_us - int((st.get("p0", [0, 0]) as Array)[1])) / 1000.0 / n, 0.01),
		"render_cpu_ms": snappedf(float(st.get("rcpu", 0.0)) / n, 0.01),
		"draw_calls": roundi(float(st["dc"]) / n),
		"primitives": roundi(float(st["prims"]) / n),
		"objects": roundi(float(st["objs"]) / n),
		"vram_mb": roundi(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6),
		"ram_mb": roundi(Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6),
		"nodes": roundi(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"enemies": g.world.enemies_root.get_child_count() if g.world else 0,
		"load_ms": int(st.get("load_ms", 0)),
		"gpu_name": RenderingServer.get_video_adapter_name(),
		"resolution": str(g.get_viewport().get_visible_rect().size),
		"class": str(g.hero.cls), "skill": str(st.get("skill", "")),
	}
	if bool(st.get("trace", false)):
		r["trace_frames"] = fr.map(func(f): return snappedf(float(f), 0.1))
		r["trace_casts"] = st["casts"]
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(r, " "))
		f.close()
	print("[KPI] ", JSON.stringify(r))
	if sc != "server":
		g.get_viewport().get_texture().get_image().save_png(out.get_basename() + ".png")
	g.get_tree().quit()
