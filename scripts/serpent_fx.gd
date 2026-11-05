class_name SerpentFx
extends RefCounted
## The Frost Serpent's effects (jj, 2026-11-04). Draws only; on the serpent's own game and its co-op puppet alike.
##  - Frost Breath ("frost_breath" "cast", then `update` for BREATH_T): a freezing gale out of its jaws along the way its
##    head points (noise-eroded cold mist billowing out and widening, ice crystals glittering in it, frost needles
##    spat out fast), a cold light riding it; the ground frosts over along the cone (FrostVolleyFx's hoarfrost); ice
##    crystal clusters burst up where the gale ends, and shatter a while later; foes in it frost over.
##  - Block: the ice shell (`shell_pose`, from SerpentBody every frame by the block's weight): a Meshy dome of jagged
##    ice (assets/models/fx/frost/ice_shell.glb, prep_prop.py; its pieces by fracture_rock.py) grows up round the
##    coiled body as the guard goes up, glowing cold; when the guard drops it shatters into its pieces.
##  - At rest, now and then a breath of cold mist out of its nostrils (`nostril_puff`).

const SHELL := "res://assets/models/fx/frost/ice_shell.glb"
const SHELL_PIECES := "res://assets/models/fx/frost/ice_shell_pieces.glb"
const SHELL_SIZE := 2.6           # the shell's scale (its model is 2 m across, 1.1 m high): the whole coil inside
const SHELL_BACK := 0.9           # metres behind the serpent's origin the coil's middle lies
const BREATH_T := 1.4
const BREATH_R := 7.0

static func _root(n: Node) -> Node3D:
	var g = n.get_tree().current_scene if n.is_inside_tree() else null
	if g != null and "world" in g and g.world != null:
		return g.world.fx_root
	return null

static func _game(n: Node):
	return n.get_tree().current_scene if n.is_inside_tree() else null

## Where the breath leaves its jaws, and the way its head points (flat-ish).
static func _jaws(h: Hero) -> Array:
	var J: Dictionary = h.rig.get_meta("j") if h.rig != null and h.rig.has_meta("j") else {}
	var hd = J.get("head")
	var at: Vector3 = h.global_position + Vector3(0, 1.6, 0) + h.facing() * 1.6
	var d: Vector3 = h.facing()
	if hd is Node3D and is_instance_valid(hd):
		var hn := hd as Node3D
		at = hn.global_position + h.facing() * 0.55 + Vector3(0, -0.1, 0)
	return [at, d]

static func play(h: Hero, ev: Dictionary) -> bool:
	if str(ev["s"]) != "frost_breath":
		return false
	match str(ev["e"]):
		"cast":
			_breath_start(h)
		_:
			return false
	return true

# ---------------------------------------------------------------- Frost Breath
static func _breath_start(h: Hero) -> void:
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var jd := _jaws(h)
	var at: Vector3 = jd[0]
	var d: Vector3 = jd[1]
	# the gale: billowing mist, glittering crystals, needles of frost, all shed into the world from the jaws
	var mist := ElementalFx._dust(root, at, FrostVolleyFx.MIST, 0.9, 0.42, {"one_shot": false, "amount": [10, 16, 24, 34][tr],
		"life": 0.75, "explosive": 0.0, "shape": "sphere", "r": 0.12, "dir": d, "spread": 16.0, "vel": [7.0, 10.0],
		"damping": [6.0, 9.0], "gravity": -0.6, "scale": [0.7, 1.2], "grow": [0.35, 3.2]})
	var glit := InfernalFx.particles(root, at, {"one_shot": false, "amount": [12, 20, 30, 44][tr], "life": 0.7,
		"explosive": 0.0, "shape": "sphere", "r": 0.1, "dir": d, "spread": 20.0, "vel": [6.0, 11.0], "damping": [4.0, 7.0],
		"gravity": -1.5, "scale": [0.4, 1.0], "size": 0.022,
		"colors": [[0.0, Color(1.3, 1.4, 1.5)], [0.6, FrostVolleyFx.PALE], [1.0, Color(FrostVolleyFx.DEEP, 0.0)]]})
	var needles := InfernalFx.particles(root, at, {"one_shot": false, "amount": [6, 10, 14, 20][tr], "life": 0.45,
		"explosive": 0.0, "shape": "sphere", "r": 0.08, "dir": d, "spread": 10.0, "vel": [12.0, 16.0], "gravity": -4.0,
		"scale": [0.5, 1.0], "size": 0.03, "colors": [[0.0, Color(1.2, 1.3, 1.4)], [1.0, Color(FrostVolleyFx.PALE, 0.0)]]})
	var lt := OmniLight3D.new()
	lt.light_color = Color(0.6, 0.82, 1.0)
	lt.light_energy = 0.0
	lt.omni_range = 7.0
	lt.shadow_enabled = false
	root.add_child(lt)
	h.fxs["breath"] = {"t": 0.0, "mist": mist, "glit": glit, "needles": needles, "light": lt, "frost": false, "ice": false}
	SkillFx.snd(h, "frost_breath", -2.0, randf_range(0.95, 1.03))
	SkillFx.shake(h, 0.06)

static func update(h: Hero, delta: float) -> void:
	if not h.fxs.has("breath"):
		return
	var b: Dictionary = h.fxs["breath"]
	b["t"] = float(b["t"]) + delta
	var t: float = b["t"]
	var root: Node3D = h.game.world.fx_root
	var tr := InfernalFx.tier(h.game)
	var jd := _jaws(h)
	var at: Vector3 = jd[0]
	var d: Vector3 = jd[1]
	var on: bool = t > 0.18 and t < BREATH_T - 0.12
	for k in ["mist", "glit", "needles"]:
		var p = b[k]
		if is_instance_valid(p):
			(p as GPUParticles3D).global_position = at
			(p as GPUParticles3D).emitting = on
			var pm := (p as GPUParticles3D).process_material as ParticleProcessMaterial
			pm.direction = d
	var lt = b["light"]
	if is_instance_valid(lt):
		(lt as OmniLight3D).global_position = at + d * 2.5
		(lt as OmniLight3D).light_energy = (1.6 if on else 0.0) * randf_range(0.85, 1.0)
	# the ground frosting over along the cone, once the gale reaches it
	if not bool(b["frost"]) and t > 0.4:
		b["frost"] = true
		var w = h.game.world
		var g: Vector3 = h.global_position
		for i in 3:
			var c: Vector3 = g + d * (2.2 + i * 2.0)
			c.y = w.height_at(c.x, c.z)
			_frost_patch(h, root, c, 1.1 + i * 0.55)
	# ice bursting up where it ends
	if not bool(b["ice"]) and t > 0.65:
		b["ice"] = true
		var g2: Vector3 = h.global_position + d * BREATH_R * 0.85
		var crystals: Array = []
		for i in [2, 3, 4, 5][tr]:
			var off := d.rotated(Vector3.UP, randf_range(-0.6, 0.6)) * randf_range(-1.2, 1.2) + d.cross(Vector3.UP) * randf_range(-1.8, 1.8)
			var p: Vector3 = g2 + off
			p.y = h.game.world.height_at(p.x, p.z)
			var cn := FrostVolleyFx._crystal(root, p, randf_range(0.5, 0.95), tr)
			if cn != null:
				crystals.append(cn)
		Sfx.play_at("ice_arrow_hit", g2, -4.0, 0.85)
		var wld = h.game.world
		Fx.later(root, 2.6, func():        # (skipped once the zone's fx_root is gone; captures no hero)
			for cn in crystals:
				if is_instance_valid(cn):
					FrostVolleyFx._break(root, wld, cn, tr)
			Sfx.play_at("ice_shatter", g2, -5.0, 1.0))
	# foes in the gale frost over
	if on and fmod(t, 0.25) < delta:
		for e in h.game.enemies_near(h.global_position + d * BREATH_R * 0.5, BREATH_R * 0.6):
			if not e.dead and (e.global_position - h.global_position).normalized().dot(d) > 0.55:
				FrostVolleyFx.frost_body(h.game, e, 2.0)
	if t > BREATH_T:
		for k in ["mist", "glit", "needles"]:
			var p = b[k]
			if is_instance_valid(p):
				(p as GPUParticles3D).emitting = false
				Fx._free_later(p as Node, 1.2)
		if is_instance_valid(lt):
			(lt as Node).queue_free()
		h.fxs.erase("breath")

## A patch of hoarfrost on the ground (FrostVolleyFx's ground shader): it spreads, holds, then thaws.
static func _frost_patch(h: Hero, root: Node3D, c: Vector3, r: float) -> void:
	var gm := FrostVolleyFx._mat("ground")
	gm.set_shader_parameter("hoar", FrostVolleyFx.hoarfrost())
	gm.set_shader_parameter("noise_tex", InfernalFx.noise())
	gm.set_shader_parameter("pale", FrostVolleyFx.PALE)
	gm.set_shader_parameter("deep", FrostVolleyFx.DEEP)
	gm.set_shader_parameter("seed", randf() * 10.0)
	gm.set_shader_parameter("tile", maxf(1.0, r * 0.55))
	var mi := ElementalFx._piece(root, InfernalFx.disc_mesh(h.game.world, c, r, 32, 5, 0.06), gm, c, 6.0)
	InfernalFx.tween_param(mi, gm, "front", 0.0, 1.0, 0.35).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(mi, gm, "thaw", 0.0, 1.0, 2.5, 3.0)

# ---------------------------------------------------------------- the ice shell (block)
## Every frame from SerpentBody with the guard's weight: grows the shell as it goes up, shatters it when it drops.
static func shell_pose(rig: Node3D, blk: float) -> void:
	var sh = rig.get_meta("ice_shell") if rig.has_meta("ice_shell") else null
	if blk > 0.55 and sh == null:
		_shell_form(rig)
	elif blk < 0.3 and sh != null:
		rig.remove_meta("ice_shell")
		if is_instance_valid(sh):
			_shell_break(rig, sh as Node3D)

static func _shell_form(rig: Node3D) -> void:
	var n := DemonKitFx.model(SHELL)
	if n == null:
		rig.set_meta("ice_shell", null)
		return
	DemonKitFx.heat_model(n, 0.7, Color(0.45, 0.75, 1.0))
	# clear ice: the coiled serpent shows through it, the edges catching the light
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var c = m.get_surface_override_material(i)
			if c is StandardMaterial3D:
				var sm := c as StandardMaterial3D
				sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				sm.albedo_color = Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b, 0.42)
				sm.roughness = 0.08
				sm.metallic_specular = 1.0
				sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	var rim := FrostVolleyFx._mat("rim")
	rim.set_shader_parameter("col", FrostVolleyFx.PALE)
	rim.set_shader_parameter("glow", 2.2)
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = rim
	# it rides on the body (moving while guarding carries it along), not turning with it
	var host := rig.get_parent() as Node3D
	if host == null:
		return
	host.add_child(n)
	n.top_level = false
	# over the middle of the coil, a little behind its head (the body lies back along its heading)
	n.position = rig.transform.basis * Vector3(0, 0, SHELL_BACK) + Vector3(0, -0.05, 0)
	n.rotation.y = randf() * TAU
	n.scale = Vector3(0.6, 0.05, 0.6) * SHELL_SIZE
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * SHELL_SIZE, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	InfernalFx.tween_param(n, rim, "glow", 4.0, 1.4, 0.5)
	rig.set_meta("ice_shell", n)
	var root := _root(rig)
	if root != null:
		var g: Vector3 = host.global_position
		ElementalFx._dust(root, g + Vector3(0, 0.15, 0), FrostVolleyFx.MIST, 1.2, 0.4, {"amount": 6, "life": 1.0,
			"explosive": 1.0, "shape": "ring", "r": 1.2, "r_in": 0.8, "dir": Vector3.UP, "spread": 20.0, "vel": [0.2, 0.6],
			"radial": [1.0, 2.0], "damping": [2.0, 3.0], "scale": [0.7, 1.1], "grow": [0.5, 1.6]})
		FrostVolleyFx._glints(root, g + Vector3(0, 1.0, 0), 10)
	var sfx: Node = rig.get_tree().root.get_node_or_null("Sfx") if rig.is_inside_tree() else null
	if sfx != null:
		sfx.call("play_at", "ice_form", host.global_position, -3.0, randf_range(0.95, 1.05))

static func _shell_break(rig: Node3D, sh: Node3D) -> void:
	var root := _root(rig)
	var g = _game(rig)
	if root == null or g == null:
		sh.queue_free()
		return
	sh.set_meta("s", SHELL_SIZE)
	FrostVolleyFx._break(root, g.world, sh, InfernalFx.tier(g), SHELL_PIECES)
	var sfx: Node = rig.get_tree().root.get_node_or_null("Sfx")
	if sfx != null:
		sfx.call("play_at", "ice_shatter", sh.global_position, -2.0, randf_range(0.85, 0.95))

## A breath of cold mist out of its nostrils (at rest, now and then; SerpentBody).
static func nostril_puff(rig: Node3D) -> void:
	var root := _root(rig)
	if root == null or not rig.has_meta("j"):
		return
	var hd = (rig.get_meta("j") as Dictionary).get("head")
	if not (hd is Node3D) or not is_instance_valid(hd):
		return
	var fwd: Vector3 = -rig.global_transform.basis.z
	var at: Vector3 = (hd as Node3D).global_position + fwd * 0.45
	ElementalFx._dust(root, at, FrostVolleyFx.MIST, 0.35, 0.3, {"amount": 4, "life": 1.4, "explosive": 0.8,
		"shape": "sphere", "r": 0.05, "dir": (fwd + Vector3.DOWN * 0.6).normalized(), "spread": 25.0, "vel": [0.4, 0.9],
		"damping": [1.5, 2.5], "gravity": -0.4, "scale": [0.6, 1.0], "grow": [0.5, 2.2]})
