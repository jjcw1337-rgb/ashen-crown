class_name BrandFx
extends RefCounted
## The Demon's Brand, seen: whoever carries it (a monster, or a player hit by his Charge, Fault or Hurl) burns with
## his sigil turning under their feet, a crimson brand burning over their head, ember motes rising off them and a
## low red light. It is the warning the whole kit hangs on: a Branded target is about to eat Molten Fists for more,
## so it has to read from any distance and angle, and most of all to the one who carries it.
##
## mark(node, secs) puts it on (or renews it), unmark(node) takes it off at once, consume(node) bursts it (the
## Fists used it up). Lives on the node itself (a child "DemonBrand"), so it follows a monster, a puppet or the hero.

const NODE := "DemonBrand"

static func mark(n: Node3D, secs: float) -> void:
	if n == null or not is_instance_valid(n) or not n.is_inside_tree() or secs <= 0.0:
		return
	var b: Node3D = n.get_node_or_null(NODE)
	var height := _height(n)
	var tr := 2
	var g = n.get("game")
	if g != null:
		tr = InfernalFx.tier(g)
	if b == null:
		b = Node3D.new()
		b.name = NODE
		n.add_child(b)
		var r := clampf(height * 0.55, 0.6, 1.6)
		# the sigil under the feet
		var sm := InfernalFx.sigil_mat()
		sm.set_shader_parameter("draw", 0.0)
		var disc := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(r * 2.0, r * 2.0)
		disc.mesh = q
		disc.material_override = sm
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		disc.position = Vector3(0, 0.06, 0)
		b.add_child(disc)
		b.set_meta("sig", sm)
		# the brand over the head: a white-hot core in a crimson bloom
		var cm := InfernalFx.glow_mat(InfernalFx.MOLTEN, 2.2, 2.6, 0.7)
		var core := InfernalFx.glow(b, n.global_position + Vector3(0, height + 0.45, 0), 0.42, cm)
		var bm := InfernalFx.glow_mat(InfernalFx.CRIMSON, 1.6, 1.4)
		var bloom := InfernalFx.glow(b, n.global_position + Vector3(0, height + 0.45, 0), 1.0, bm)
		b.set_meta("core", cm)
		b.set_meta("bloom", bm)
		core.position = Vector3(0, height + 0.45, 0)
		bloom.position = core.position
		# ember motes rising off the body
		var em := InfernalFx.particles(b, n.global_position + Vector3(0, height * 0.5, 0), {"amount": [6, 10, 14, 18][tr],
			"life": 0.9, "one_shot": false, "shape": "sphere", "r": height * 0.35, "dir": Vector3.UP, "spread": 20.0,
			"vel": [0.6, 1.4], "gravity": 0.8, "scale": [0.5, 1.0], "size": 0.05,
			"colors": [[0.0, Color(InfernalFx.CRIMSON, 0.0)], [0.25, InfernalFx.BLOODFIRE], [0.7, InfernalFx.MOLTEN], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
		em.position = Vector3(0, height * 0.5, 0)
		b.set_meta("em", em)
		if tr >= 1:
			var l := OmniLight3D.new()
			l.light_color = InfernalFx.BLOODFIRE
			l.light_energy = 0.0
			l.omni_range = 2.6
			l.shadow_enabled = false
			l.position = Vector3(0, height * 0.6, 0)
			b.add_child(l)
			b.set_meta("light", l)
		var snd_at := n.global_position
		Sfx.play_at("fire_erupt", snd_at, -14.0, 1.5)
	var old = b.get_meta("tw") if b.has_meta("tw") else null
	if old != null and (old as Tween).is_valid():
		(old as Tween).kill()
	var tw := b.create_tween()
	tw.tween_method(func(t: float): _tick(b, t, secs), 0.0, secs, secs)
	tw.tween_callback(func(): _drop(b))
	b.set_meta("tw", tw)

## The look over its life: the sigil draws itself, turns, pulses; the last second it gutters out.
static func _tick(b: Node3D, t: float, secs: float) -> void:
	if not is_instance_valid(b):
		return
	var draw := clampf(t / 0.22, 0.0, 1.0)
	var fade := clampf((secs - t) / 0.8, 0.0, 1.0)
	var pulse := 0.75 + 0.25 * sin(t * 7.0)
	var sm: ShaderMaterial = b.get_meta("sig")
	sm.set_shader_parameter("draw", draw)
	sm.set_shader_parameter("spin", t * 1.4)
	sm.set_shader_parameter("flare", (1.0 - clampf(t / 0.3, 0.0, 1.0)) * 1.2 + 0.25 * pulse)
	sm.set_shader_parameter("life", fade)
	(b.get_meta("core") as ShaderMaterial).set_shader_parameter("alpha", fade * pulse)
	(b.get_meta("bloom") as ShaderMaterial).set_shader_parameter("alpha", fade * 0.55 * pulse)
	if b.has_meta("light"):
		var l = b.get_meta("light")
		if is_instance_valid(l):
			(l as OmniLight3D).light_energy = 1.1 * fade * pulse
	if fade < 0.5 and b.has_meta("em"):
		(b.get_meta("em") as GPUParticles3D).emitting = false

static func _drop(b: Node3D) -> void:
	if is_instance_valid(b):
		b.queue_free()

static func unmark(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	var b = n.get_node_or_null(NODE)
	if b != null:
		(b as Node).queue_free()

static func has(n: Node) -> bool:
	return n != null and is_instance_valid(n) and n.get_node_or_null(NODE) != null

## Molten Fists used it up: the sigil flares white and bursts in a ring of crimson fire.
static func consume(n: Node3D) -> void:
	if not has(n):
		return
	var root: Node3D = n.get_parent() as Node3D
	var g = n.get("game")
	if g != null and g.world != null:
		root = g.world.fx_root
	var height := _height(n)
	var at := n.global_position
	var gm := InfernalFx.glow_mat(InfernalFx.WHITEHOT, 2.6, 2.0, 0.8)
	var gl := InfernalFx.glow(root, at + Vector3(0, height + 0.45, 0), 0.5, gm)
	gl.create_tween().tween_property(gl, "scale", Vector3.ONE * 2.6, 0.22).set_ease(Tween.EASE_OUT)
	InfernalFx.tween_param(gl, gm, "alpha", 1.0, 0.0, 0.25)
	Fx._free_later(gl, 0.3)
	InfernalFx.particles(root, at + Vector3(0, 0.15, 0), {"amount": 26, "life": 0.5, "explosive": 1.0, "shape": "ring",
		"r": 0.5, "r_in": 0.35, "dir": Vector3.UP, "spread": 80.0, "vel": [2.0, 4.5], "gravity": -3.0, "radial": [3.0, 6.0],
		"damping": [2.0, 3.0], "scale": [0.5, 1.0], "size": 0.08,
		"colors": [[0.0, InfernalFx.WHITEHOT], [0.35, InfernalFx.BLOODFIRE], [1.0, Color(InfernalFx.CRIMSON, 0.0)]]})
	Sfx.play_at("hellclaw", at, -6.0, 1.3)
	unmark(n)

static func _height(n: Node) -> float:
	var h = n.get("height")
	if h != null and float(h) > 0.2:
		return float(h)
	return 2.0
