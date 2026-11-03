extends SceneTree
## Frame statistics and screenshots per zone and graphics preset, for the visual overhaul's before/after:
##   xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 -s tools/visual_audit/frame_stats.gd -- \
##       out_dir zone[,zone...] [--quality 0,1,2,3] [--frames N] [--noshot] [--class knight] [--zoom 1.0] [--at x,z]
## Zones as in scene_census.gd (town wild lair coast a2_wild a2_town a2_lair a3_wild bg). For each preset it loads the
## zone (so per-preset grass density applies), lets it settle, then averages N frames of what the renderer reports:
## draw calls, primitives and objects for the scene pass and the shadow passes separately
## (RenderingServer.viewport_get_render_info), video memory, and saves <zone>_q<N>.png. Writes <out_dir>/stats.json
## (appending runs) and prints one line per zone and preset. Counts don't depend on the GPU, so the cloud's software
## renderer gives the same numbers as a real card; frame times here mean nothing (use --kpi on real hardware).

var g
var out_dir := "build/visual_audit/frames"
const ZONES := {
	"town": [0, "town"], "wild": [0, "wild"], "lair": [0, "lair"], "coast": [0, "coast"],
	"a2_wild": [1, "wild"], "a2_town": [1, "town"], "a2_lair": [1, "lair"],
	"a3_wild": [2, "wild"], "bg": [0, "bg"],
}

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func _arg(args: PackedStringArray, key: String, def: String) -> String:
	var i := args.find(key)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if args.size() > 0 else out_dir
	var zones: PackedStringArray = (args[1] if args.size() > 1 else "town").split(",")
	var qs: PackedStringArray = _arg(args, "--quality", "2").split(",")
	var frames := int(_arg(args, "--frames", "3"))
	var cls := _arg(args, "--class", "knight")
	var zoom := float(_arg(args, "--zoom", "1.0"))
	var at := _arg(args, "--at", "")
	var shots := not args.has("--noshot")
	DirAccess.make_dir_recursive_absolute(out_dir)
	while g.world == null or g._busy:
		g._intro_skip = true
		await process_frame
	await g.start_game(false, cls)
	g.ui.close_all()
	var results: Array = []
	var vp := get_root().get_viewport_rid()
	for z in zones:
		if not ZONES.has(z):
			print("[FRAME] unknown zone ", z)
			continue
		for qs_ in qs:
			var q := int(qs_)
			g.apply_quality(q)
			g.difficulty = int(ZONES[z][0])
			var t0 := Time.get_ticks_msec()
			await g.load_zone(0, ZONES[z][1], "start")
			var load_ms := Time.get_ticks_msec() - t0
			g.apply_quality(q)
			if args.has("--fast"):
				# counts only: screen-space effects and multisampling add no geometry passes, so switching them off
				# leaves draw calls and primitives unchanged and makes the software renderer several times faster
				g.env.ssao_enabled = false
				g.env.ssil_enabled = false
				g.env.volumetric_fog_enabled = false
				g.env.glow_enabled = false
				g.env.ssr_enabled = false
				get_root().msaa_3d = Viewport.MSAA_DISABLED
			if at != "":
				var p := at.split(",")
				var pos := Vector3(float(p[0]), 0.0, float(p[1]))
				pos.y = g.world.height_at(pos.x, pos.z)
				g.hero.global_position = pos
				g.cam_target = pos
			g.zoom = zoom
			g.ui.close_all()
			# settle: the camera glides to the hero, shadows and LODs pick up, the grass field fills
			for i in int(_arg(args, "--settle", "6")):
				await process_frame
			var acc := {"vis_draw": 0.0, "vis_prims": 0.0, "vis_objs": 0.0, "sh_draw": 0.0, "sh_prims": 0.0, "sh_objs": 0.0,
				"tot_draw": 0.0, "tot_prims": 0.0, "tot_objs": 0.0}
			for i in frames:
				await process_frame
				acc["vis_draw"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
				acc["vis_prims"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
				acc["vis_objs"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
				acc["sh_draw"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
				acc["sh_prims"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
				acc["sh_objs"] += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
				acc["tot_draw"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				acc["tot_prims"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				acc["tot_objs"] += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			for k in acc.keys():
				acc[k] = roundf(float(acc[k]) / frames)
			var r := {"zone": z, "quality": q, "load_ms": load_ms, "frames": frames, "vram_mb": roundf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6),
				"tex_mb": roundf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6),
				"buf_mb": roundf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6), "renderer": "Forward+" if g.is_forward() else "Compatibility",
				"time": Time.get_datetime_string_from_system()}
			r.merge(acc)
			results.append(r)
			print("[FRAME] %s q%d: scene %d draws %s prims %d objs | shadow %d draws %s prims %d objs | total %d draws %s prims | vram %d MB (tex %d) | load %d ms" % [
				z, q, acc["vis_draw"], _m(acc["vis_prims"]), acc["vis_objs"], acc["sh_draw"], _m(acc["sh_prims"]), acc["sh_objs"],
				acc["tot_draw"], _m(acc["tot_prims"]), r["vram_mb"], r["tex_mb"], load_ms])
			# every other viewport that drew this frame (SubViewports share the frame's totals)
			var vps := []
			for n in get_root().find_children("*", "SubViewport", true, false):
				var sv := n as SubViewport
				var rid := sv.get_viewport_rid()
				var vprims := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
				var sprims := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
				var info := {"path": str(sv.get_path()).right(70), "size": "%dx%d" % [sv.size.x, sv.size.y], "update": sv.render_target_update_mode,
					"own_world": sv.own_world_3d, "no3d": sv.disable_3d, "prims": vprims, "shadow_prims": sprims}
				vps.append(info)
				if vprims + sprims > 0 or sv.render_target_update_mode == SubViewport.UPDATE_ALWAYS:
					print("[FRAME]   subviewport %s %s update %d own_world %s: %s prims + %s shadow" % [info["path"], info["size"], info["update"], info["own_world"], _m(vprims), _m(sprims)])
			r["subviewports"] = vps
			if shots:
				var img := get_root().get_texture().get_image()
				img.save_png(out_dir.path_join("%s_q%d.png" % [z, q]))
	var path := out_dir.path_join("stats.json")
	var all: Array = []
	if FileAccess.file_exists(path):
		var prev = JSON.parse_string(FileAccess.get_file_as_string(path))
		if prev is Array:
			all = prev
	all.append_array(results)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(all, " "))
	f.close()
	g.difficulty = 0
	quit()

static func _m(v) -> String:
	var x := float(v)
	if x >= 1e6:
		return "%.2fM" % (x / 1e6)
	if x >= 1e3:
		return "%.0fk" % (x / 1e3)
	return str(int(x))
