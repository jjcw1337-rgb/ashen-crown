extends SceneTree
## Frames of the Plague Doctor's six skills in a row, for the gameplay video. Needs a display (xvfb) and
## --fixed-fps 30 so the frames are 1/30 s apart whatever the render takes:
##   xvfb-run -a godot --rendering-driver opengl3 --path . --resolution 1280x720 --fixed-fps 30 \
##     -s heroes/plague/tools/plague_kit_clip.gd -- <outdir> [skills,comma,separated|all] [view game|close] [quality]
## Each skill gets its own fresh pack and its own seconds (`PLAN`); frames are numbered straight through
## (<outdir>/f_NNNN.png) and <outdir>/segments.txt lists where each skill starts, for titles. "fever" (not in
## "all") is Blight and Fever on one foe: vial, swarm and bloom in turn, Blight marks stacking, then the Fever.
## "pvp" and "break" (not in "all") are the Battlegrounds: another player (a knight, a puppet as a partner's game
## would show him) under his statuses (PvpStatusFx: roots, flies, Blight, Fever and the eye), and that player
## breaking his Corpse Bloom and then his vat while he cranks it (PvpObjects, the blows counted on his game).
var g

## skill -> [seconds, foes, foes fight back]
const PLAN := {
	"toxic": [4.0, 4, false],
	"swarm": [5.5, 4, true],
	"bloom": [5.5, 3, false],
	"fog": [4.0, 3, true],
	"transfusion": [4.0, 4, true],
	"experiment": [10.5, 5, true],
	"fever": [7.0, 1, false],
	"pvp": [8.0, 0, false],
	"break": [8.6, 0, false],
}
const EXTRA := ["fever", "pvp", "break"]

func _initialize():
	g = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(g)
	_run()

func wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var which: String = args[1] if args.size() > 1 else "all"
	var view: String = args[2] if args.size() > 2 else "game"
	var quality: int = int(args[3]) if args.size() > 3 else 0
	var skills: Array = PLAN.keys().filter(func(k): return not EXTRA.has(k)) if which == "all" else Array(which.split(","))
	while g.world == null or g._busy or g._intro_playing:
		g._intro_skip = true
		await process_frame
	g.apply_quality(0)
	await g.start_game(false, "plague")
	g.ui.close_all()
	await g.load_zone(0, "wild", "road")
	g.ui.close_all()
	var h = g.hero
	h.level = 24
	h.recalc()
	g.test_immortal = true
	g.zoom = 0.66
	g.ui.visible = false
	(g.vignette.material as ShaderMaterial).set_shader_parameter("strength", 0.4)
	g.apply_quality(quality)
	if quality == 0:
		g.sun.shadow_enabled = false
		get_root().msaa_3d = Viewport.MSAA_DISABLED
	var cam := Camera3D.new()
	cam.fov = 40
	cam.near = 3.5      # the close view sits ~9.5 m off: cut the bushes between it and him
	get_root().add_child(cam)
	var seg := FileAccess.open(out + "/segments.txt", FileAccess.WRITE)
	var fno := 0
	var home: Vector3 = h.global_position
	for sk in skills:
		var plan: Array = PLAN[sk]
		for e in g.enemies_near(home, 80.0):
			e.queue_free()
		if h.pd != null:
			h.pd.clear()
		await process_frame
		h.global_position = home
		h.life = h.max_life
		h.mana = h.max_mana
		for k in h.cds.keys():
			h.cds[k] = 0.0
		h._face(Vector3(0, 0, -1))
		var foes := []
		var n: int = plan[1]
		var dist := 6.5 if sk != "transfusion" and sk != "fog" else 2.2
		for i in n:
			var a := 0.0 if n == 1 else -0.7 + 1.4 * float(i) / maxf(n - 1, 1)
			var p: Vector3 = home + Vector3(sin(a) * dist, 0, -cos(a) * dist) + Vector3(0, 0, -0.6 * (i % 2))
			p = g.world.free_spot_near(p, 0.5)
			var e = g.spawn_enemy("zombie" if i % 3 != 2 else "fallen", p, 24)
			e.max_life = 6000.0
			e.life = 6000.0
			if not bool(plan[2]):
				e.aggro = false
				e.scripted = 99.0
			foes.append(e)
		var center: Vector3 = home + Vector3(0, 0, -dist)
		if sk in ["pvp", "break"]:
			_rival_at(h, g.world.free_spot_near(center + (Vector3(1.4, 0, 0.6) if sk == "break" else Vector3.ZERO), 0.5))
		elif rival != null and is_instance_valid(rival):
			rival.visible = false
		await wait(0.3)
		seg.store_line("%d %s" % [fno, sk])
		var frames: int = int(float(plan[0]) * 30.0)
		for f in frames:
			var live := foes.filter(func(e): return is_instance_valid(e) and not e.dead)
			var aim: Vector3 = center
			if not live.is_empty():
				aim = live[(f / 40) % live.size()].global_position
			match sk:
				"toxic":
					if f == 6 or f == 62:
						_use(h, "toxic", aim)
				"swarm":
					if f == 6:
						_use(h, "swarm", center)
					if f == 80:
						_use(h, "swarm", center + Vector3(2.5, 0, 1.0))
				"bloom":
					if f == 6:
						# beside the middle foe, who stands still, so its roots get him in plain view of the camera
						var mid: Vector3 = center
						var best := 1e9
						for e in live:
							var dd: float = (e.global_position - center).length()
							if dd < best:
								best = dd
								mid = e.global_position
						_use(h, "bloom", mid + Vector3(-1.7, 0, 0.5))
				"fog":
					if f == 8:
						_use(h, "fog", center)
				"transfusion":
					if f == 10:
						_use(h, "transfusion", h.global_position)
				"experiment":
					if f == 6:
						_use(h, "experiment", center + Vector3(0, 0, 1.0))
				"fever":
					# three different skills on the one foe: a Blight mark each, then the Fever
					# each as soon as the last move has finished (a cast mid-throw is refused)
					if f >= 6 and fever_step < 3 and h.atk_t < 0.0:
						var ids := ["toxic", "swarm", "bloom"]
						var at: Vector3 = aim + (Vector3(-1.6, 0, 0.6) if fever_step == 2 else Vector3.ZERO)
						if _use(h, ids[fever_step], at):
							fever_step += 1
				"pvp":
					_pvp_frame(h, f)
				"break":
					_break_frame(h, f)
			if view == "close":
				cam.current = true
				var c: Vector3 = center.lerp(h.global_position, 0.4)
				var off := Vector3(5.5, 6.0, 5.0)
				var look_y := 0.6
				if sk == "transfusion":
					# a self-buff: in on him
					c = h.global_position
					off = Vector3(3.4, 3.0, 3.0)
				elif sk == "fever":
					# in on the foe who gathers the Blight
					c = aim
					off = Vector3(3.6, 3.8, 3.4)
				elif sk == "pvp":
					# in on the other player, high enough for the marks and the eye over his head
					c = rival_spot.lerp(h.global_position, 0.12)
					off = Vector3(4.2, 3.0, 4.0)
					look_y = 1.5
				elif sk == "break":
					c = rival_spot.lerp(h.global_position, 0.25)
					off = Vector3(4.6, 4.8, 4.2)
				cam.global_transform = Transform3D(Basis(), c + off).looking_at(c + Vector3(0, look_y, 0))
			else:
				g.cam.current = true
			await process_frame
			await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png("%s/f_%04d.png" % [out, fno])
			fno += 1
	seg.close()
	quit()

var fever_step := 0

# ---------------------------------------------------------------- the Battlegrounds segments
var rival: Hero = null
var rival_spot := Vector3.ZERO
var rival_walk := []          # [from, to, start frame, frames]
var swing_at := -1            # the frame his swing began
var break_id := 0

## The other player: a knight as a partner's game shows him (a puppet posed from what his game sends).
func _rival_at(h: Hero, at: Vector3) -> void:
	if h.pd != null:
		h.pd.clear()
	if rival == null or not is_instance_valid(rival):
		rival = Hero.new()
		rival.puppet = true
		rival.peer_id = 99
		rival.name = "Rival99"
		g.add_child(rival)
		rival.setup(g)
		rival.apply_net_gear({"_cls": "knight", "_helm": true, "weapon": Items.make("broad_sword"), "shield": Items.make("buckler"), "armor": Items.make("chain_mail")})
	rival.visible = true
	rival.trail.visible = false     # (his sword's trail draws as a white slab on the cloud's software renderer)
	rival_spot = at
	rival.global_position = at
	rival.net_has = true
	rival.net_pvs_bits = 0
	rival.net_pvs_blight = 0
	rival_walk = []
	swing_at = -1
	break_id = 0
	_rival_pose(h.global_position, 0, 0.0)

func _rival_pose(look: Vector3, f: int, move: float) -> void:
	if rival_walk.size() == 4:
		var k := clampf(float(f - int(rival_walk[2])) / float(rival_walk[3]), 0.0, 1.0)
		rival_spot = (rival_walk[0] as Vector3).lerp(rival_walk[1], k)
		rival_spot.y = g.world.height_at(rival_spot.x, rival_spot.z)
		if k < 1.0:
			move = 0.55
			look = rival_walk[1]
	var d := look - rival_spot
	rival.net_pos = rival_spot
	rival.net_yaw = atan2(-d.x, -d.z)
	var atk := -1.0
	if swing_at >= 0 and f - swing_at < 18:
		atk = float(f - swing_at) / 18.0
	rival.net_st = {"move": move, "atk": atk, "style": "swipe1" if atk >= 0.0 else "over", "block": 0.0, "hit": 0.0}

func _walk(to: Vector3, f: int, n: int) -> void:
	rival_walk = [rival_spot, to, f, n]

## His statuses on the other player, at the moments his skills put them there: the bloom's pulse roots him and
## Blights him, the swarm harries and Blights him, the vial makes three: Fever, and Fever reveals him.
var pulse_f := -1
var vial_f := -1
func _pvp_frame(h: Hero, f: int) -> void:
	if f == 0:
		pulse_f = -1
		vial_f = -1
	if f == 6:
		_use(h, "bloom", rival_spot + Vector3(-1.7, 0, 0.5))
	if f == 40:
		_use(h, "swarm", rival_spot)
	if f == 120:
		_use(h, "toxic", rival_spot)
	if pulse_f < 0 and not h.pd.blooms.is_empty() and is_instance_valid(h.pd.blooms[0]["node"]) and int(h.pd.blooms[0]["node"].get("last_pulse")) >= 1:
		pulse_f = f
	if vial_f < 0 and h.pd.clouds.any(func(c) -> bool: return c["src"] == "toxic"):
		vial_f = f
	var bits := 0
	var bl := 0
	if not h.pd.swarm.is_empty() and (h.pd.swarm["pos"] as Vector3).distance_to(rival_spot) < Plague.SWARM_R:
		bits |= PvpStatusFx.HARRIED
		bl = 1
	if pulse_f >= 0:
		bl += 1
		if f - pulse_f < 18:
			bits |= PvpStatusFx.SNARE
	if vial_f >= 0:
		bl = 3
		bits |= PvpStatusFx.REVEAL
	rival.net_pvs_bits = bits
	rival.net_pvs_blight = bl
	_rival_pose(h.global_position, f, 0.0)

## The other player breaks his things: three blows kill his Corpse Bloom early, three on the vat while he cranks it
## and the experiment fails (each blow counted on the Doctor's game, as the server would pass it on).
var vat_f := -1
func _break_frame(h: Hero, f: int) -> void:
	if f == 0:
		vat_f = -1
	var target := h.global_position
	if f == 6:
		_use(h, "bloom", rival_spot + Vector3(-1.6, 0, -0.3))
	if f == 26 and not h.pd.blooms.is_empty():
		break_id = int(h.pd.blooms[0]["oid"])
		var bp: Vector3 = h.pd.blooms[0]["pos"]
		_walk(bp + (rival_spot - bp).normalized() * 1.25, f, 16)
	if not h.pd.blooms.is_empty():
		target = h.pd.blooms[0]["pos"]
	if f in [50, 69, 88]:
		swing_at = f
	if f in [60, 79, 98] and break_id > 0:
		h.pd.obj_hit(break_id, 99)
	if f == 124:
		_use(h, "experiment", rival_spot + Vector3(-1.5, 0, -0.8))
	if not h.pd.lab.is_empty():
		target = h.pd.lab["pos"]
		if vat_f < 0 and int(h.pd.lab.get("stage", 0)) == 1:
			vat_f = f
	# three blows on the vat while he cranks it, one every 0.63 s (the server lets one through per 0.6 s)
	if vat_f >= 0:
		var t := f - vat_f
		if t in [4, 23, 42]:
			swing_at = f
		if t in [14, 33, 52] and not h.pd.lab.is_empty() and int(h.pd.lab.get("stage", 0)) == 1:
			h.pd.obj_hit(int(h.pd.lab.get("oid", 0)), 99)
	_rival_pose(target, f, 0.0)

func _use(h, id: String, at: Vector3) -> bool:
	h.cds[id] = 0.0
	h.mana = h.max_mana
	h.cursor = at
	return h.use_skill(id, h.skill_aim(id, at))
