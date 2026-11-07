class_name GlacialTombFx
extends RefCounted
## Glacial Tomb's look (GlacialTomb): the serpent's own ice shell (SerpentFx.SHELL, its block's) closing over each foe
## sealed, rime crawling up them (FrostFx.frost_body) ("seal"), the shells following their foes (`update`, Hero.fxs
## "drg_tombs"), then broken into their fractured pieces in a frost nova ("shatter"; a lost shatter: each breaks by
## itself when its time is up). Draws only.

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"seal":
			var shells: Array = h.fxs.get("drg_tombs", [])
			for e in ev.get("t", []):
				if not is_instance_valid(e):
					continue
				var n := _ice_shell(root, e as Node3D)
				if n != null:
					shells.append({"n": n, "e": e, "t": float(ev.get("x", 1.6)) + 0.6})
				FrostFx.frost_body(h.game, e, float(ev.get("x", 1.6)) + 0.4)
			h.fxs["drg_tombs"] = shells
			var p: Vector3 = ev["p"]
			FrostFx.glints(root, p + Vector3(0, 1.2, 0), 12)
			ElementalFx._dust(root, p + Vector3(0, 0.2, 0), FrostFx.MIST, 1.6, 0.45, {"amount": 10, "life": 1.4,
				"explosive": 1.0, "shape": "ring", "r": 1.6, "r_in": 0.6, "dir": Vector3.UP, "spread": 25.0, "vel": [0.2, 0.6],
				"radial": [0.6, 1.6], "damping": [2.0, 3.0], "scale": [0.8, 1.3], "grow": [0.6, 1.8]})
			SkillFx.snd(h, "ice_tomb_seal", 0.0)
		"shatter":
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
		_:
			return false
	return true

## Every frame (on the caster and everyone else's copy of it): the shells follow their foes.
static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("drg_tombs"):
		return
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

static func clear(h: Hero) -> void:
	for sh in h.fxs.get("drg_tombs", []):
		if is_instance_valid(sh["n"]):
			(sh["n"] as Node).queue_free()
	h.fxs.erase("drg_tombs")

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
	var rim := FrostFx.mat("rim")
	rim.set_shader_parameter("col", FrostFx.PALE)
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
	FrostFx.smash(root, h.game.world, n as Node3D, InfernalFx.tier(h.game), SerpentFx.SHELL_PIECES)
