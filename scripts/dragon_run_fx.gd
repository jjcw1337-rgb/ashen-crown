class_name DragonRunFx
extends RefCounted
## The look of the dragons' run skills (DragonSkills: Data.RUN_SKILLS), built from their own kits' assets:
##   Frost Serpent  Glacial Tomb  the Meshy ice shell (its own block's) closing over each foe with rime crawling up
##                                them (FrostVolleyFx.frost_body), then broken into its fractured pieces in a frost nova
##                  Crushing Coil the tail spin's crush: the ground cracked and thrown up (ElementalFx.ground_slam)
##                                and cold mist rolled out over it
##                  Rime Lance    a line of the Meshy ice crystals bursting up one after another, then shattering
##   Storm Wyvern   Thunder Dive  up on its beating wings (the dodge's flight pose, the rig's "fly" meta), down in a
##                                strike of the Blender-rendered lightning, the ground cracked and scorched
##                  Thunderhead   the ash cloud book darkened to a storm over the pointer, its bolts into the foes
##                  Gale Wings    one great wingbeat: dust driven out in a cone, the grass flattened
## Effects only: nothing here touches life, cooldowns or stuns (a puppet has none). State that runs on is in
## h.fxs["drg_*"], moved by update() on the caster and on his puppet alike.

const STORM_TINT := Color(0.3, 0.33, 0.42)
const DIVE_H := 7.0               # metres up at the top of the dive
const CLOUD_Y := 8.5

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var game = h.game
	match [str(ev["s"]), str(ev["e"])]:
		["s_tomb", "seal"]:
			var shells: Array = h.fxs.get("drg_tombs", [])
			for e in ev.get("t", []):
				if not is_instance_valid(e):
					continue
				var n := _ice_shell(root, e as Node3D)
				if n != null:
					shells.append({"n": n, "e": e, "t": float(ev.get("x", 1.6)) + 0.6})
				FrostVolleyFx.frost_body(game, e, float(ev.get("x", 1.6)) + 0.4)
			h.fxs["drg_tombs"] = shells
			var p: Vector3 = ev["p"]
			FrostVolleyFx._glints(root, p + Vector3(0, 1.2, 0), 12)
			ElementalFx._dust(root, p + Vector3(0, 0.2, 0), FrostVolleyFx.MIST, 1.6, 0.45, {"amount": 10, "life": 1.4,
				"explosive": 1.0, "shape": "ring", "r": 1.6, "r_in": 0.6, "dir": Vector3.UP, "spread": 25.0, "vel": [0.2, 0.6],
				"radial": [0.6, 1.6], "damping": [2.0, 3.0], "scale": [0.8, 1.3], "grow": [0.6, 1.8]})
			SkillFx.snd(h, "ice_tomb_seal", 0.0)
		["s_tomb", "shatter"]:
			var p2: Vector3 = ev["p"]
			var shells2: Array = h.fxs.get("drg_tombs", [])
			var gone: Array = ev.get("t", [])
			for i in range(shells2.size() - 1, -1, -1):
				var sh: Dictionary = shells2[i]
				if gone.has(sh["e"]) or not is_instance_valid(sh["e"]):
					_break(h, root, sh["n"])
					shells2.remove_at(i)
			ElementalFx.frost_nova(h, root, p2, float(ev.get("r", 3.0)))
			SkillFx.snd(h, "ice_shatter", 0.0, 0.85)
			SkillFx.shake(h, 0.3)
			SkillFx.hitstop(h, 0.05)
		["s_coil", "crush"]:
			var p3: Vector3 = ev["p"]
			var r: float = float(ev.get("r", 4.2))
			ElementalFx.ground_slam(game, root, p3, r)
			ElementalFx._dust(root, p3 + Vector3(0, 0.25, 0), FrostVolleyFx.MIST, 1.8, 0.5, {"amount": 12, "life": 1.3,
				"explosive": 1.0, "shape": "ring", "r": 1.0, "r_in": 0.5, "dir": Vector3.UP, "spread": 10.0, "vel": [0.1, 0.4],
				"radial": [4.0, 6.5], "damping": [2.5, 3.5], "scale": [0.9, 1.4], "grow": [0.6, 1.8]})
			for e in ev.get("t", []):
				if is_instance_valid(e):
					Fx.streaks(root, (e as Node3D).global_position + Vector3(0, 1.0, 0), [[0.0, Color(0.9, 0.96, 1.0)], [1.0, Color(0.5, 0.75, 1.0, 0.0)]], 8, 5.0, 0.04, 3.0, 0.35, true, -6.0)
			SkillFx.shake(h, 0.28)
			SkillFx.snd(h, "slam", -4.0, 0.8)
		["s_lance", "spikes"]:
			var p4: Vector3 = ev["p"]
			var d: Vector3 = ev["d"]
			var ln: float = float(ev.get("x", 10.0))
			var tr := InfernalFx.tier(game)
			var step: float = [1.6, 1.3, 1.1, 1.0][tr]
			var k := 0
			var along := 1.2
			while along <= ln:
				var side := Vector3(d.z, 0, -d.x) * randf_range(-0.35, 0.35)
				var at: Vector3 = p4 + d * along + side
				at.y = game.world.height_at(at.x, at.z)
				_spike(h, root, at, randf_range(0.55, 0.85) + along / ln * 0.25, k * 0.045, tr)
				along += step
				k += 1
			SkillFx.snd(h, "ice_burst", -2.0, 1.1)
			SkillFx.shake(h, 0.18)
		["v_dive", "start"]:
			h.fxs["drg_dive"] = {"t": 0.0, "dur": float(ev.get("x", 1.0))}
			Dodge._wing_gust(h, 1.3)
			ArcFx.charge(h, DragonSkills.jaws(h), WYVERN, 0.35)
		["v_dive", "land"]:
			_dive_end(h)
			var p5: Vector3 = ev["p"]
			var r2: float = float(ev.get("r", 4.0))
			ArcFx.bolt(root, p5 + Vector3(randf_range(-1, 1), 16.0, randf_range(-1, 1)), p5 + Vector3(0, 0.2, 0), 0.35, 1.6, WYVERN, game)
			ElementalFx.ground_slam(game, root, p5, r2)
			ArcFx._scorch(root, p5, r2 * 0.55)
			for e in ev.get("t", []):
				if is_instance_valid(e):
					ArcFx._struck(h, root, (e as Node3D).global_position + Vector3(0, 1.0, 0), WYVERN)
			ArcFx._flash(root, p5 + Vector3(0, 1.5, 0), WYVERN[1], 6.0, 0.3, r2 * 2.5)
			Dodge._wing_gust(h, 1.8)
			SkillFx.snd(h, "thunder_blast", 0.0, 1.0)
			SkillFx.shake(h, 0.45)
			SkillFx.hitstop(h, 0.06)
		["v_cloud", "form"]:
			var p6: Vector3 = ev["p"]
			var secs: float = float(ev.get("x", 4.0))
			var clouds: Array = h.fxs.get("drg_clouds", [])
			var c1 := DemonKitFx.smoke(root, p6 + Vector3(0, CLOUD_Y, 0), "ash", 11.0, secs + 1.0, true, STORM_TINT)
			var c2 := DemonKitFx.smoke(root, p6 + Vector3(1.5, CLOUD_Y + 0.6, -1.0), "ash", 8.0, secs + 1.0, true, STORM_TINT * 0.8)
			clouds.append({"p": p6, "n": [c1, c2], "t": secs + 1.0})
			h.fxs["drg_clouds"] = clouds
			ArcFx.bolt(root, p6 + Vector3(0, CLOUD_Y, 0), p6 + Vector3(randf_range(-3, 3), CLOUD_Y - 2.0, randf_range(-3, 3)), 0.3, 0.8, WYVERN, game)
			SkillFx.snd(h, "thunderhead", -2.0)
		["v_cloud", "bolt"]:
			var q: Vector3 = ev["q"]
			var top: Vector3 = (ev["p"] as Vector3) + Vector3(randf_range(-2, 2), CLOUD_Y - 0.5, randf_range(-2, 2))
			ArcFx.bolt(root, top, q + Vector3(0, 1.0, 0), 0.25, 1.1, WYVERN, game)
			ArcFx._struck(h, root, q + Vector3(0, 1.0, 0), WYVERN)
			ArcFx._flash(root, q + Vector3(0, 2.0, 0), WYVERN[1], 3.0, 0.18, 7.0)
			SkillFx.snd(h, "arc_zap", -5.0, randf_range(0.8, 0.95))
		["v_cloud", "end"]:
			var p7: Vector3 = ev["p"]
			var clouds2: Array = h.fxs.get("drg_clouds", [])
			for i in range(clouds2.size() - 1, -1, -1):
				if (clouds2[i]["p"] as Vector3).distance_to(p7) < 0.5:
					_cloud_out(clouds2[i])
					clouds2.remove_at(i)
		["v_gale", "gust"]:
			var p8: Vector3 = ev["p"]
			var d2: Vector3 = ev["d"]
			var r3: float = float(ev.get("r", 6.5))
			Dodge._wing_gust(h, 2.0)
			SkillFx.snd(h, "gale_gust", 0.0)
			var tr2 := InfernalFx.tier(game)
			ElementalFx._dust(root, p8 + d2 * 1.2 + Vector3(0, 0.4, 0), Color(0.62, 0.6, 0.55), 1.5, 0.55, {"amount": [8, 12, 16, 22][tr2],
				"life": 1.1, "explosive": 1.0, "shape": "point", "dir": d2 + Vector3(0, 0.12, 0), "spread": 38.0, "vel": [r3 * 1.4, r3 * 2.2],
				"damping": [2.5, 3.5], "scale": [0.8, 1.3], "grow": [0.8, 2.2]})
			GrassField.impulse(p8 + d2 * r3 * 0.5, r3 * 0.6, 1.0, 0.5)
			for e in ev.get("t", []):
				if is_instance_valid(e):
					Fx.streaks(root, (e as Node3D).global_position + Vector3(0, 1.2, 0), [[0.0, Color(0.95, 0.95, 0.9)], [1.0, Color(0.6, 0.6, 0.55, 0.0)]], 6, 6.0, 0.03, 4.0, 0.3, true, -3.0, 50.0, ev["d"])
			SkillFx.shake(h, 0.2)
		_:
			return false
	return true

## Every frame (caster and puppet): the dive's height and wingbeats, the tombs following their foes, the clouds' end.
static func update(h: Hero, delta: float) -> void:
	if h.fxs.has("drg_dive"):
		var dv: Dictionary = h.fxs["drg_dive"]
		dv["t"] = float(dv["t"]) + delta
		var a := clampf(float(dv["t"]) / maxf(float(dv["dur"]), 0.01), 0.0, 1.0)
		var f := clampf((a - DragonSkills.DIVE_FLY.x) / (DragonSkills.DIVE_FLY.y - DragonSkills.DIVE_FLY.x), 0.0, 1.0)
		if a >= 1.0 or h.rig == null:
			_dive_end(h)
		else:
			# up fast, a hang at the top, then a steep drop onto them (the impact is the landing)
			var up := sin(PI * pow(f, 0.7)) if f < 1.0 else 0.0
			h.rig.position.y = DIVE_H * up
			h.rig.rotation.x = 0.35 * smoothstep(0.55, 0.95, f) - 0.2 * (1.0 - smoothstep(0.0, 0.4, f)) * float(f > 0.0)
			h.rig.set_meta("fly", f)
	if h.fxs.has("drg_tombs"):
		var shells: Array = h.fxs["drg_tombs"]
		for i in range(shells.size() - 1, -1, -1):
			var sh: Dictionary = shells[i]
			sh["t"] = float(sh["t"]) - delta
			var n = sh["n"]
			if not is_instance_valid(n):
				shells.remove_at(i)
				continue
			if is_instance_valid(sh["e"]) and not sh["e"].dead:
				(n as Node3D).global_position = (sh["e"] as Node3D).global_position
			if float(sh["t"]) <= 0.0 or not is_instance_valid(sh["e"]):
				_break(h, h.game.world.fx_root, n)        # (a lost shatter event: it breaks by itself)
				shells.remove_at(i)
	if h.fxs.has("drg_clouds"):
		var clouds: Array = h.fxs["drg_clouds"]
		for i in range(clouds.size() - 1, -1, -1):
			clouds[i]["t"] = float(clouds[i]["t"]) - delta
			if float(clouds[i]["t"]) <= 0.0:
				_cloud_out(clouds[i])
				clouds.remove_at(i)

static func clear(h: Hero) -> void:
	_dive_end(h)
	for sh in h.fxs.get("drg_tombs", []):
		if is_instance_valid(sh["n"]):
			(sh["n"] as Node).queue_free()
	for cl in h.fxs.get("drg_clouds", []):
		_cloud_out(cl)
	h.fxs.erase("drg_tombs")
	h.fxs.erase("drg_clouds")

static func _dive_end(h: Hero) -> void:
	if not h.fxs.has("drg_dive"):
		return
	h.fxs.erase("drg_dive")
	if h.rig != null:
		h.rig.position = Vector3.ZERO
		h.rig.rotation.x = 0.0
		if h.rig.has_meta("fly"):
			h.rig.remove_meta("fly")

static func _cloud_out(cl: Dictionary) -> void:
	for n in cl["n"]:
		if is_instance_valid(n):
			DemonKitFx.smoke_out(n, 0.8)

## The serpent's own ice shell (SerpentFx.SHELL), clear and rimmed, closing over a foe.
static func _ice_shell(root: Node3D, e: Node3D) -> Node3D:
	var n := DemonKitFx.model(SerpentFx.SHELL)
	if n == null:
		return null
	DemonKitFx.heat_model(n, 0.7, Color(0.45, 0.75, 1.0))
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var c = m.get_surface_override_material(i)
			if c is StandardMaterial3D:
				var sm := c as StandardMaterial3D
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sm.albedo_color = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, 0.5)
				sm.roughness = 0.08
				sm.metallic_specular = 1.0
				sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	var rim := FrostVolleyFx._mat("rim")
	rim.set_shader_parameter("col", FrostVolleyFx.PALE)
	rim.set_shader_parameter("glow", 2.4)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = rim
	root.add_child(n)
	n.global_position = e.global_position
	n.rotation.y = randf() * TAU
	# a dome over it: as wide as the foe and a little more, tall enough to close over its head
	var rad: float = float(e.get("radius")) if e.get("radius") != null else 0.6
	var hgt: float = float(e.get("height")) * 2.0 if e.get("height") != null else 1.8
	var s := maxf(0.9, rad * 1.6 + 0.4)
	var sy := maxf(s, hgt / 1.1 * 1.05)
	n.set_meta("s", s)
	n.scale = Vector3(s * 0.5, 0.05, s * 0.5)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3(s, sy, s), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	InfernalFx.tween_param(n, rim, "glow", 4.0, 1.4, 0.5)
	return n

static func _break(h: Hero, root: Node3D, n) -> void:
	if not is_instance_valid(n):
		return
	FrostVolleyFx._break(root, h.game.world, n as Node3D, InfernalFx.tier(h.game), SerpentFx.SHELL_PIECES)

## One of the Rime Lance's crystals: up after `delay`, shattered a moment later.
static func _spike(h: Hero, root: Node3D, at: Vector3, s: float, delay: float, tr: int) -> void:
	var tw := root.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if not is_instance_valid(root):
			return
		var c := FrostVolleyFx._crystal(root, at, s, tr)
		if c == null:
			return
		var t2 := c.create_tween()
		t2.tween_interval(0.9 + randf() * 0.3)
		t2.tween_callback(func():
			if is_instance_valid(c) and is_instance_valid(h):
				FrostVolleyFx._break(root, h.game.world, c, tr)))

# ---------------------------------------------------------------- the Storm Wyvern's Storm Arc
## The Storm Wyvern's lightning palette: core, glow (ArcFx).
const WYVERN := [Color(0.92, 1.0, 0.98), Color(0.3, 0.9, 1.0)]

## The Storm Wyvern's Storm Arc, drawn with the shared lightning (ArcFx; SkillFx.play hands a dragon's events here).
static func storm_arc(h: Hero, ev: Dictionary) -> bool:
	if str(ev["s"]) != "storm_arc":
		return false
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			ArcFx.charge(h, DragonSkills.jaws(h), WYVERN, 0.45)
			_wing_crackle(h)
		"impact":
			ArcFx.chain(h, root, ev["ps"], ev["d"], WYVERN, 1.25)
			SkillFx.shake(h, 0.12)
		_:
			return false
	return true

## The wyvern's wings crackling as it rears: arcs running out along each wing's bones.
static func _wing_crackle(h: Hero) -> void:
	var sk := h.rig.find_children("*", "Skeleton3D", true, false)
	if sk.is_empty():
		return
	var s := sk[0] as Skeleton3D
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	for side in ["L", "R"]:
		var chain_b: Array = []
		for nm in ["arm_%s_0" % side, "arm_%s_1" % side, "fing0_%s_0" % side, "fing0_%s_1" % side, "fing1_%s_1" % side]:
			var i := s.find_bone(nm)
			if i >= 0:
				chain_b.append(s.global_transform * s.get_bone_global_pose(i).origin)
		for k in chain_b.size() - 1:
			ElementalFx.bolt(root, chain_b[k], chain_b[k + 1], 0.3, 0.035, tr, WYVERN[0], WYVERN[1])
