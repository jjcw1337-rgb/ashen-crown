class_name Kpi
## The official performance KPIs (docs/nightly/KPIS.md): fixed, scripted scenarios measured the same way every time,
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
	"crypt": {"zone": "bg", "run": 0, "secs": 20.0, "what": "Battlegrounds Hollow Crypt: walking the corridors and rooms, fighting what's there"},
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
			st["t0"] = Time.get_ticks_usec()
		return
	(st["frames"] as Array).append(delta * 1000.0)
	st["proc"] = float(st["proc"]) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	st["phys"] = float(st["phys"]) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	st["dc"] = float(st["dc"]) + Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	st["prims"] = float(st["prims"]) + Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	st["objs"] = float(st["objs"]) + Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	if sc != "server":
		st["gpu"] = float(st["gpu"]) + RenderingServer.viewport_get_measured_render_time_gpu(g.get_viewport().get_viewport_rid())
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
			if pi >= 0 and pi + 1 < a.size():
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
				for s in h.skill_list():
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
