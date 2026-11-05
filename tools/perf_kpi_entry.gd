extends SceneTree
## Audit-only wrapper: deterministic RNG, local backend and isolated character storage.
## Use through tools/_late.gd with the normal --kpi arguments and an isolated user directory.
var g
var last_usec := 0
var last_phase := ""
var walls: Array = []
var deltas: Array = []
var query_start: Array = []
var query_end: Array = []
var render_scales := {}
var focus_states := {}
var requested_focus := false

func _initialize() -> void:
	seed(420042)
	BuildEnv.forced = {"env": "local", "cloud": "0", "nakama_url": "http://127.0.0.1:1"}
	g = (load("res://main.tscn") as PackedScene).instantiate()
	g.char_dir = "user://perf_verify_chars/"
	g.rng.seed = 420042
	get_root().add_child(g)
	g.rng.seed = 420042 # Game._ready randomizes it; reset before deferred KPI zone loading.
	g.set_sound(false)
	print("[VERIFY] viewport=", get_root().get_visible_rect().size, " window=", get_root().size,
		" user=", OS.get_user_data_dir())

func _process(delta: float) -> bool:
	var now := Time.get_ticks_usec()
	var phase := str(Kpi.st.get("phase", ""))
	if phase == "settle" and not requested_focus and OS.get_cmdline_user_args().has("--foreground"):
		get_root().grab_focus()
		requested_focus = true
	if phase == "measure" and last_phase == "measure":
		render_scales[str(get_root().scaling_3d_scale)] = true
		focus_states[str(get_root().has_focus())] = true
		walls.append((now - last_usec) / 1000.0)
		deltas.append(delta * 1000.0)
		query_end = g.get_meta("audit_query", [0, 0])
	elif phase == "measure":
		query_start = g.get_meta("audit_query", [0, 0])
	last_usec = now
	last_phase = phase
	return false

func _finalize() -> void:
	if Kpi.out == "":
		return
	var data := {"wall_frames_ms": walls, "engine_deltas_ms": deltas,
		"observed_render_scales": render_scales.keys(),
		"observed_window_focus": focus_states.keys(),
		"query_start": query_start, "query_end": query_end,
		"pipeline_cache": ProjectSettings.get_setting("rendering/rendering_device/pipeline_cache/enable"),
		"user_dir": OS.get_user_data_dir()}
	var f := FileAccess.open(Kpi.out.get_basename() + ".audit.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
