extends SceneTree
## A partner's view of a hero's skills: the hero casts into a pack while his pose and every fx event are
## recorded; then a puppet of him (Hero.puppet, as a partner sees him) plays the recording back beside an
## identical pack, far from the hero, and the camera watches the puppet. Needs a display (xvfb) and --fixed-fps 30:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s tools/coop_fx_shot.gd -- <outdir> [class:skill,...]
## Writes <outdir>/<class>_<skill>_NNN.png (every 5th frame of the playback).
var g
const SHOTS := ["wraith:siphon", "wraith:grasp", "wraith:night", "warlock:drain", "demon:grip", "demon:wrath", "archer:volley"]
const SECS := {"siphon": 3.6, "grasp": 3.0, "night": 6.6, "phantom": 2.6, "drain": 3.2, "volley": 2.8, "cleave": 2.0,
	"fists": 2.0, "icharge": 2.6, "cslam": 3.6, "hurl": 3.2, "grip": 3.2, "wrath": 9.0,
	"pie": 1.8, "peels": 2.4, "slide": 1.8, "doppel": 3.4, "juggle": 2.6, "bounce": 2.4, "car": 6.4}
const OFF := Vector3(40.0, 0, 0)
var off := OFF            # to the puppet's spot, the ground's height there included
var puppet: Hero

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _pack(at: Vector3, n: int, lvl: int, dist := 4.5) -> Array:
	var out := []
	for i in n:
		var p := at + Vector3(-1.1 + i * 1.1, 0, -dist - absf(i - 1) * 0.5)
		var e = g.spawn_enemy("zombie", p, lvl)
		e.aggro = false
		e.scripted = 99.0
		out.append(e)
	return out

## An event moved over to the puppet's spot: points shifted, enemies swapped for the puppet's own pack.
## A spot OFF away from home (or the clearest of a ring of such spots) with no tree trunk within 9 m and room for
## the pack, so the camera isn't buried in a canopy.
func _clearing(home: Vector3) -> Vector3:
	var best := home + OFF
	var best_d := -1.0
	for i in 12:
		var ang := i * TAU / 12.0
		var p := home + Vector3(cos(ang) * OFF.x, 0, sin(ang) * OFF.x)
		if g.world.is_blocked(p.x, p.z) or g.world.is_blocked(p.x, p.z - 5.0) or g.world.is_blocked(p.x + 5.0, p.z):
			continue
		var d := 999.0
		for t in g.world.tree_pts:
			d = minf(d, Vector2(p.x, p.z).distance_to(t))
		if d > best_d:
			best_d = d
			best = p
	return best

func _shift(w: Dictionary, from_pack: Array, to_pack: Array) -> Dictionary:
	var ev := SkillFx.decode(g.net, w)
	for k in ["p", "q"]:
		if ev.has(k):
			ev[k] = (ev[k] as Vector3) + off
	if ev.has("ps"):
		var ps: PackedVector3Array = ev["ps"]
		for i in ps.size():
			ps[i] += off
		ev["ps"] = ps
	if ev.has("t"):
		var out := []
		for e in ev["t"]:
			var i := from_pack.find(e)
			if i >= 0 and i < to_pack.size() and is_instance_valid(to_pack[i]):
				out.append(to_pack[i])
		ev["t"] = out
	return ev

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var shots: Array = SHOTS if args.size() < 2 else Array(args[1].split(","))
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(0)     # software GL under xvfb: the Low preset before any zone is built (grass, shadows)
	var cls_now := ""
	var cam := Camera3D.new()
	cam.fov = 38
	get_root().add_child(cam)
	for shot in shots:
		var cls: String = shot.split(":")[0]
		var sk: String = shot.split(":")[1]
		if cls != cls_now:
			cls_now = cls
			await g.start_game(false, cls)
			g.ui.close_all()
			await g.load_zone(0, "sandbox", "start")
			g.ui.close_all()
			g.hero.level = 20
			g.hero.recalc()
			g.test_immortal = true
			g.ui.visible = false
			(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.0)
			g.apply_quality(0)
			g.sun.shadow_enabled = false
			get_root().msaa_3d = Viewport.MSAA_DISABLED
			if puppet != null and is_instance_valid(puppet):
				puppet.queue_free()
			puppet = Hero.new()
			puppet.puppet = true
			puppet.peer_id = 99
			puppet.name = "Ally99"
			g.add_child(puppet)
			puppet.setup(g)
			puppet.apply_net_gear(g.hero.net_gear())
			puppet.light.light_energy = 0.5
		var h = g.hero
		for e in g.enemies_near(h.global_position, 80.0):
			e.queue_free()
		await process_frame
		var home: Vector3 = h.global_position
		var there := _clearing(home)
		there.y = g.world.height_at(there.x, there.z)
		off = there - home
		var n := 1 if sk in ["siphon", "drain"] else 3
		var dist := 2.4 if sk == "grip" else 4.5      # Hellgrip only reaches 3.6 m
		var pack: Array = _pack(home, n, 24, dist)
		h._face(Vector3(0, 0, -1))
		for k in h.cds.keys():
			h.cds[k] = 0.0
		h.mana = h.max_mana
		h.life = h.max_life * 0.6
		await wait(0.3)
		# record: the pose each frame and the events it sent
		var rec: Array = []
		var evs: Array = []
		g.net.fx_tap = func(w: Dictionary): evs.append(w)
		var frames: int = int(float(SECS.get(sk, 2.6)) * 30)
		var aim: Vector3 = pack[n / 2].global_position
		for f in frames:
			if f == 6:
				h.use_skill(sk, h.skill_aim(sk, aim) if Data.skill_def(sk).get("aim", "facing") == "facing" else aim)
			await process_frame
			var st: Dictionary = h.last_pose.duplicate()
			st.erase("time")
			st.erase("phase")
			rec.append({"pos": h.global_position, "yaw": h.rig.rotation.y, "st": st, "ev": evs.duplicate()})
			evs.clear()
		g.net.fx_tap = Callable()
		h.end_channel()
		WraithSkills.clear(h)
		DemonSkills.clear(h)
		# the puppet plays it back far away, beside its own pack; the hero waits out of sight
		var pack2: Array = _pack(there, n, 24, dist)
		h.global_position = home + Vector3(0, 0, 60.0)
		puppet.global_position = there
		puppet.net_pos = there
		puppet.net_yaw = rec[0]["yaw"]
		puppet.net_st = rec[0]["st"]
		puppet.net_has = true
		puppet.visible = true
		await wait(0.3)
		var i := 0
		for r in rec:
			puppet.net_pos = (r["pos"] as Vector3) + off
			puppet.net_yaw = r["yaw"]
			puppet.net_st = r["st"]
			for w in r["ev"]:
				SkillFx.play(puppet, _shift(w, pack, pack2))
			cam.current = true
			var c: Vector3 = there
			var off := Vector3(4.2, 2.3, 0.4)
			var look := c + Vector3(0, 0.9, -2.4)
			if sk == "night":
				off = Vector3(7.0, 3.6, -1.0)
				look = c + Vector3(0, 1.5, -1.5)
			elif sk in ["drain", "volley", "cleave"]:
				off = Vector3(5.0, 2.8, 0.6)
				look = c + Vector3(0, 0.9, -2.8)
			elif sk == "wrath":
				off = Vector3(8.0, 4.5, 0.5)
				look = c + Vector3(0, 1.2, -2.5)
			elif sk in ["cslam", "hurl", "icharge"]:
				off = Vector3(6.5, 3.6, 1.0)
				look = c + Vector3(0, 0.8, -4.0)
			cam.global_transform = Transform3D(Basis(), c + off).looking_at(look)
			await process_frame
			await RenderingServer.frame_post_draw
			if i % 5 == 0:
				get_root().get_texture().get_image().save_png("%s/%s_%s_%03d.png" % [out, cls, sk, i])
			i += 1
		SkillFx.clear(puppet)
		for e in pack2:
			if is_instance_valid(e):
				e.queue_free()
		h.global_position = home
		h.life = h.max_life
		await wait(0.5)
	quit()
