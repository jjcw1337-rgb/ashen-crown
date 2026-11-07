class_name SerpentFx
extends RefCounted
## The Frost Serpent's effects (jj, 2026-11-04). Draws only; on the serpent's own game and everyone else's copy of it.
## Its skills' looks are in their folders: Frost Breath (skills/frost_breath/frost_breath_fx.gd), Glacial Tomb,
## Crushing Coil and Rime Lance (skills/<skill>/<skill>_fx.gd); `play`, `update` and `clear` hand their events on
## (SkillFx). Its body's own look is here:
##  - Block: the ice shell (`shell_pose`, from SerpentBody every frame by the block's weight): a Meshy dome of jagged
##    ice (assets/models/fx/frost/ice_shell.glb, prep_prop.py; its pieces by fracture_rock.py) grows up round the
##    coiled body as the guard goes up, glowing cold; when the guard drops it shatters into its pieces. Glacial Tomb
##    closes the same shell over its foes.
##  - At rest, now and then a breath of cold mist out of its nostrils (`nostril_puff`).

const SHELL := "res://assets/models/fx/frost/ice_shell.glb"
const SHELL_PIECES := "res://assets/models/fx/frost/ice_shell_pieces.glb"
const SHELL_SIZE := 2.6           # the shell's scale (its model is 2 m across, 1.1 m high): the whole coil inside
const SHELL_BACK := 0.9           # metres behind the serpent's origin the coil's middle lies

static func _root(n: Node) -> Node3D:
	var g = n.get_tree().current_scene if n.is_inside_tree() else null
	if g != null and "world" in g and g.world != null:
		return g.world.fx_root
	return null

static func _game(n: Node):
	return n.get_tree().current_scene if n.is_inside_tree() else null

## One of its skills' events (SkillFx.play): true when it was drawn.
static func play(h: Hero, ev: Dictionary) -> bool:
	match str(ev["s"]):
		"frost_breath": return FrostBreathFx.play(h, ev)
		"s_tomb": return GlacialTombFx.play(h, ev)
		"s_coil": return CrushingCoilFx.play(h, ev)
		"s_lance": return RimeLanceFx.play(h, ev)
	return false

## Every frame, on every hero (each look keeps its own state in Hero.fxs): the breath blowing, the tombs following
## their foes.
static func update(h: Hero, delta: float) -> void:
	FrostBreathFx.update(h, delta)
	GlacialTombFx.update(h, delta)

## Everything of its that lingers is let go.
static func clear(h: Hero) -> void:
	FrostBreathFx.clear(h)
	GlacialTombFx.clear(h)

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
	var rim := FrostFx.mat("rim")
	rim.set_shader_parameter("col", FrostFx.PALE)
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
		ElementalFx._dust(root, g + Vector3(0, 0.15, 0), FrostFx.MIST, 1.2, 0.4, {"amount": 6, "life": 1.0,
			"explosive": 1.0, "shape": "ring", "r": 1.2, "r_in": 0.8, "dir": Vector3.UP, "spread": 20.0, "vel": [0.2, 0.6],
			"radial": [1.0, 2.0], "damping": [2.0, 3.0], "scale": [0.7, 1.1], "grow": [0.5, 1.6]})
		FrostFx.glints(root, g + Vector3(0, 1.0, 0), 10)
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
	FrostFx.smash(root, g.world, sh, InfernalFx.tier(g), SHELL_PIECES)
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
	ElementalFx._dust(root, at, FrostFx.MIST, 0.35, 0.3, {"amount": 4, "life": 1.4, "explosive": 0.8,
		"shape": "sphere", "r": 0.05, "dir": (fwd + Vector3.DOWN * 0.6).normalized(), "spread": 25.0, "vel": [0.4, 0.9],
		"damping": [1.5, 2.5], "gravity": -0.4, "scale": [0.6, 1.0], "grow": [0.5, 2.2]})
