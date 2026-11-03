class_name PvpStatusFx
extends RefCounted
## What the statuses another player put on a hero look like (PvP, `PvpStatus`), on his own screen and on everyone
## else's: his game puts them in his state packet (`Net._hero_packet`: `bits_of` and `blight_of`), and a puppet shows
## what it was sent, so everyone sees the same thing (after the server's diminishing returns and any cleanse). Each is
## built from the Plague Doctor's own Meshy and Blender assets, so it reads as his doing:
##   snare    the Meshy thorned roots (roots.glb) burst up round his feet and hold them, sinking when he's free
##   harried  a knot of the Meshy flies (the swarm's fly and flock shader) buzzing round his head and shoulders
##   slow     a sick green mist round his feet: the fog's wisp simulation rolling low, the vapour curling up
##   reveal   the Meshy eye sigil over his head: he can be seen through Fog of the Forgotten
##   blight   the Meshy Blight marks over his head, one per stack; at three they burst into Fever (PlagueFever)
## `sync` does nothing while nothing changed (the hero keeps what is shown in `Hero.pvs_shown`).

const SNARE := 1
const HARRIED := 2
const SLOW := 4
const REVEAL := 8
const EYE_TEX := "res://assets/textures/plague/reveal_eye.png"

static var _roots: PackedScene
static var _eye_mat: StandardMaterial3D

## The bits of a hero's own statuses (`Hero.pvs`).
static func bits_of(h: Hero) -> int:
	if h.pvs.is_empty() and not h.cc.has("slow"):
		return 0
	var b := 0
	if PvpStatus.has(h, "snare"):
		b |= SNARE
	if PvpStatus.has(h, "harried"):
		b |= HARRIED
	if PvpStatus.has(h, "slow") and str(h.cc["slow"].get("src", "")) == "pd":
		b |= SLOW
	if PvpStatus.has(h, "reveal"):
		b |= REVEAL
	return b

## His Blight stacks (3 = Feverish).
static func blight_of(h: Hero) -> int:
	if h.pvs.is_empty():
		return 0
	return clampi(int(round(PvpStatus.strength(h, "blight"))), 0, 3)

## Shows exactly `bits` and `blight` on the hero: adds what is new, takes away what ended.
static func sync(h: Hero, bits: int, blight: int) -> void:
	blight = clampi(blight, 0, 3)
	var key := (bits & 15) | (blight << 4)
	var was := maxi(h.pvs_shown, 0)
	if key == was:
		h.pvs_shown = key
		return
	h.pvs_shown = key
	var now := bits & 15
	var before := was & 15
	if (now & SNARE) and not (before & SNARE):
		_snare(h)
	elif (before & SNARE) and not (now & SNARE):
		_sink(h, "pvs_snare")
	if (now & HARRIED) and not (before & HARRIED):
		_harried(h)
	elif (before & HARRIED) and not (now & HARRIED):
		_end(h, "pvs_harried", 0.6)
	if (now & SLOW) and not (before & SLOW):
		_slow(h)
	elif (before & SLOW) and not (now & SLOW):
		_end(h, "pvs_slow", 1.2)
	if (now & REVEAL) and not (before & REVEAL):
		_reveal(h)
	elif (before & REVEAL) and not (now & REVEAL):
		_end(h, "pvs_reveal", 0.0)
	var bl_before := (was >> 4) & 3
	if blight != bl_before:
		if blight >= 3:
			# the marks burst into Fever
			PlagueFever.stacks(h, 0)
			PlagueFever.fever(h, float(PvpStatus.MAX["blight"]))
		else:
			PlagueFever.stacks(h, blight)
			if bl_before >= 3:
				var fv := h.get_node_or_null("pd_fever")
				if fv != null:
					h.remove_child(fv)
					fv.queue_free()

## A node made for a status leaves at once (its name is free again for the next one) and goes after `linger`.
static func _end(h: Hero, nm: String, linger: float) -> void:
	var n := h.get_node_or_null(nm)
	if n == null:
		return
	n.name = nm + "_gone"
	var parts := n.find_children("*", "GPUParticles3D", true, false)
	if n is GPUParticles3D:
		parts.append(n)
		# the harried flies scatter off him (the swarm's own scatter), not just vanish
		var sm := (n as GPUParticles3D).process_material as ShaderMaterial
		if sm != null:
			sm.set_shader_parameter("scatter", 1.0)
	for p in parts:
		(p as GPUParticles3D).emitting = false
	if linger <= 0.0:
		n.queue_free()
	else:
		Fx._free_later(n, linger)

static func _sink(h: Hero, nm: String) -> void:
	var n := h.get_node_or_null(nm) as Node3D
	if n == null:
		return
	n.name = nm + "_gone"
	var m: Node3D = null
	if n.get_child_count() > 0:
		m = n.get_child(0) as Node3D
	if m == null:
		n.queue_free()
		return
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3(m.scale.x * 1.08, 0.02, m.scale.z * 1.08), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(n.queue_free)

## Rooted: the bloom's thorned roots burst up round his feet and hold them.
static func _snare(h: Hero) -> void:
	if _roots == null and ResourceLoader.exists(PlagueBloomFx.ROOTS_GLB):
		_roots = load(PlagueBloomFx.ROOTS_GLB)
	var root := Node3D.new()
	root.name = "pvs_snare"
	h.add_child(root)
	root.rotation.y = randf() * TAU
	if _roots != null:
		var m: Node3D = _roots.instantiate()
		root.add_child(m)
		var k := (h.radius * 2.0 + 0.7) / 1.05
		m.position = Vector3(0, -0.06, 0)
		m.scale = Vector3(k * 0.7, 0.02, k * 0.7)
		var tw := m.create_tween()
		tw.tween_property(m, "scale", Vector3(k, k * 0.85, k), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.burst(root, h.global_position + Vector3(0, 0.2, 0), Color(0.18, 0.13, 0.1), 14, 2.2, 0.05, 0.5, false, -9.0, 70.0)

## Harried: a knot of the swarm's flies buzzing round his head.
static func _harried(h: Hero) -> void:
	var p := GPUParticles3D.new()
	p.name = "pvs_harried"
	p.amount = 34
	p.lifetime = 30.0
	p.explosiveness = 0.9
	p.local_coords = true
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6))
	var mat := ShaderMaterial.new()
	mat.shader = PlagueSwarmFx._process_shader()
	# they burst out at his chest (the node sits 1.35 m up) and wheel in a band from the shoulders to over the hat,
	# 0.45-1.1 m out from him (the body is ~0.4 m across)
	mat.set_shader_parameter("target", Vector3(0, -0.45, 0))
	mat.set_shader_parameter("radius", 0.65)
	mat.set_shader_parameter("core", 0.45)
	mat.set_shader_parameter("tall", 0.75)
	mat.set_shader_parameter("scatter", 0.0)
	mat.set_shader_parameter("home", 0.0)
	p.process_material = mat
	p.draw_pass_1 = PlagueSwarmFx._fly_mesh()
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(p)
	p.position = Vector3(0, 1.35, 0)
	p.emitting = true
	# a thin dark haze of the swarm's vapour round his head, so it reads from the game camera too
	var hz := PlagueSmoke.vapour(p, Color(0.06, 0.08, 0.04, 0.4), 7, 0.9, 1.2, 0.08, 0.5, Vector3(0, 0.25, 0), Color(0.03, 0.06, 0.015))
	hz.name = "haze"

## Slowed: a sick green mist clinging round his feet: a low bank of the fog's wisp simulation rolling round his
## boots, the vapour curling up off it to his knees.
static func _slow(h: Hero) -> void:
	var v := PlagueSmoke.vapour(h, Color(0.48, 0.7, 0.26, 0.55), 10, 1.3, 1.6, 0.04, h.radius + 0.3, Vector3(0, 0.12, 0), Color(0.06, 0.12, 0.025), PlagueSmoke.WISP, true)
	v.name = "pvs_slow"
	var up := PlagueSmoke.vapour(v, Color(0.5, 0.74, 0.28, 0.4), 8, 0.6, 1.1, 0.25, h.radius + 0.1, Vector3(0, 0.15, 0), Color(0.04, 0.08, 0.02))
	up.name = "curl"

## Revealed: the eye sigil over his head (seen through Fog of the Forgotten).
static func _reveal(h: Hero) -> void:
	var tex := PlagueVialFx._tex(EYE_TEX)
	if tex == null:
		return
	if _eye_mat == null:
		_eye_mat = StandardMaterial3D.new()
		_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_eye_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_eye_mat.albedo_texture = tex
	var m := MeshInstance3D.new()
	m.name = "pvs_reveal"
	var q := QuadMesh.new()
	q.size = Vector2(0.52, 0.52)
	m.mesh = q
	m.material_override = _eye_mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.add_child(m)
	# over the Blight marks (2.5 m), so the two read apart when both are on him
	m.position = Vector3(0, 3.0, 0)
	m.scale = Vector3.ONE * 0.2
	var tw := m.create_tween()
	tw.tween_property(m, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# then it hangs there, bobbing slowly like the marks
	var bob := m.create_tween().set_loops()
	bob.tween_property(m, "position:y", 3.08, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(m, "position:y", 2.96, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
