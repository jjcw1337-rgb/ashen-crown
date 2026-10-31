class_name SlothLair
extends Node3D
## A Hollow Sloth's lair (Act I, sloth.gd): a clearing far off the road where it lives and wanders, dressed
## for its element. Cinder Hollow (fire): scorched black earth with glowing lava cracks, charred trees and
## lava-veined boulders, flames and drifting embers. Rimefrost Glade (cold): frost-white glittering ground,
## ice crystal clusters and frozen boulders, frost mist. Stormcall Ring (lightning): scorched ground with
## violet fissures, a ring of rune stones and a lightning-split tree, bolts striking the stones now and then.
## The ground is a Decal of procedural textures; the pieces are Meshy props (assets/models/lairs/), or
## simple stand-ins without them. World._sloths picks the places (before the trees, which keep out of them).

## the clearing (no trees), where it wanders, and the edge you cross to wake it
const CLEAR := 12.0
const TERRITORY := 8.0
const BOUNDARY := 13.0

const NAMES := {"fire": "Cinder Hollow", "cold": "Rimefrost Glade", "lightning": "Stormcall Ring"}
const PROPS := "res://assets/models/lairs/%s.glb"

var element := ""
var col := Color.WHITE
var light: OmniLight3D
var stones: Array = []      # the storm's rune stones (bolts strike them)
var _t := 0.0
var _bolt_t := 2.0

## Three places for the lairs: one in each stretch of the moor, well off the road on the side with room,
## inside the bounds with room for the clearing, far from each other and from the camp and landmarks.
static func pick(w: World) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = int(w.bounds.size.y * 1000.0) + 5151
	var out := []
	var inner: Rect2 = w.bounds.grow(-CLEAR - 1.0)
	for i in 3:
		var best := Vector3.INF
		for tries in 60:
			var t := 0.25 + 0.3 * i + r.randf_range(-0.07, 0.07)
			var c: Vector2 = w.path_poly[int((w.path_poly.size() - 1) * clampf(t, 0.05, 0.95))]
			var side := -signf(c.x) if absf(c.x) > 4.0 else (1.0 if r.randf() < 0.5 else -1.0)
			var p := Vector3(c.x + side * r.randf_range(20.0, 32.0), 0, c.y + r.randf_range(-6.0, 6.0))
			if not inner.has_point(Vector2(p.x, p.z)) or w.path_dist(p.x, p.z) < CLEAR + 8.0:
				continue
			if Vector2(p.x, p.z).distance_to(Vector2(0, -6)) < 45.0 or w.is_near_obstacle(p, CLEAR * 0.6):
				continue
			if out.any(func(q): return (q as Vector3).distance_to(p) < 50.0):
				continue
			best = p
			break
		if best != Vector3.INF:
			out.append(best)
	return out

static func make(w: World, at: Vector3, el: String) -> SlothLair:
	var l := SlothLair.new()
	l.element = el
	l.col = Sloth.ELEMENTS[el]["col"]
	l.name = "lair_" + el
	w.props_root.add_child(l)
	l.position = Vector3(at.x, w.height_at(at.x, at.z), at.z)
	l._dress(w)
	return l

func _dress(w: World) -> void:
	add_child(_ground())
	light = OmniLight3D.new()
	light.light_color = col
	light.light_energy = 2.4
	light.omni_range = CLEAR * 1.5
	light.position = Vector3(0, 5.0, 0)
	add_child(light)
	var r := RandomNumberGenerator.new()
	r.seed = int(absf(global_position.x) * 131.0 + absf(global_position.z) * 17.0)
	match element:
		"fire":
			for k in 3:
				var a := TAU * k / 3.0 + r.randf_range(-0.3, 0.3)
				_piece(w, "fire_tree", a, r.randf_range(8.5, 10.5), 5.5 * r.randf_range(0.85, 1.15), 0.5, r)
			for k in 4:
				var a := TAU * (k + 0.5) / 4.0 + r.randf_range(-0.3, 0.3)
				var rock := _piece(w, "fire_rock", a, r.randf_range(6.5, 10.0), 1.8 * r.randf_range(0.8, 1.3), 1.0, r)
				Props.fire(rock, Vector3(0, 1.0, 0), 0.8, Color(1.0, 0.45, 0.12), k == 0, true)
			var em := Fx.aura(self, Color(1.0, 0.45, 0.08, 0.9), 140, 0.8, 0.1, 3.5, 0.5, CLEAR * 0.8, 30.0, Vector3(0, 0.3, 0), false)
			(em.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			(em.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(CLEAR * 0.8, 0.1, CLEAR * 0.8)
		"cold":
			for k in 5:
				var a := TAU * k / 5.0 + r.randf_range(-0.25, 0.25)
				_piece(w, "ice_crystals", a, r.randf_range(7.5, 10.5), 2.4 * r.randf_range(0.8, 1.3), 0.8, r)
			for k in 3:
				var a := TAU * (k + 0.5) / 3.0 + r.randf_range(-0.3, 0.3)
				_piece(w, "ice_rock", a, r.randf_range(6.0, 9.5), 1.9 * r.randf_range(0.85, 1.25), 1.0, r)
			var mist := Fx.aura(self, Color(0.85, 0.93, 1.0, 0.35), 40, 0.15, 1.2, 4.0, 0.02, CLEAR * 0.7, 90.0, Vector3(0, 0.3, 0), false)
			(mist.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			(mist.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(CLEAR * 0.75, 0.1, CLEAR * 0.75)
			var glit := Fx.aura(self, Color(0.6, 0.85, 1.0), 50, 0.1, 0.05, 2.5, -0.15, CLEAR * 0.7, 180.0, Vector3(0, 2.5, 0))
			(glit.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			(glit.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(CLEAR * 0.75, 1.5, CLEAR * 0.75)
		"lightning":
			for k in 7:
				var a := TAU * k / 7.0
				stones.append(_piece(w, "storm_stone", a, 9.5, 3.3 * r.randf_range(0.85, 1.15), 0.6, r, true))
			_piece(w, "storm_tree", r.randf() * TAU, 5.5, 5.0, 0.5, r)
			var sp := Fx.aura(self, Color(0.45, 0.32, 0.6), 30, 1.5, 0.05, 0.4, 0.0, CLEAR * 0.7, 180.0, Vector3(0, 0.5, 0))
			(sp.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			(sp.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(CLEAR * 0.75, 0.3, CLEAR * 0.75)

## One piece of the lair at angle a, distance d from the centre, h metres tall, solid with radius fr.
func _piece(w: World, kind: String, a: float, d: float, h: float, fr: float, r: RandomNumberGenerator, face_in := false) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	root.set_meta("lair_piece", kind)
	var path := PROPS % kind
	if ResourceLoader.exists(path):
		var m: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(m)
		m.scale = Vector3.ONE * h
	else:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = fr * 0.3 if kind.ends_with("tree") or kind.ends_with("crystals") else fr * 0.8
		cm.bottom_radius = fr
		cm.height = h
		mi.mesh = cm
		mi.position.y = h * 0.5
		mi.material_override = Mats.mat(col.darkened(0.6), 0.8, 0.0, col, 0.4)
		root.add_child(mi)
	var p := global_position + Vector3(cos(a) * d, 0, sin(a) * d)
	root.rotation.y = (-a + PI * 0.5) if face_in else r.randf() * TAU
	# trees by their trunk, the rest by their bulk (the props are modelled 1 m tall and scaled to h)
	Props.footprint(root, fr if kind.ends_with("tree") else fr * clampf(h / 2.0, 0.7, 1.6))
	w.props_root.add_child(root)
	root.position = Vector3(p.x, w.height_at(p.x, p.z) - 0.05, p.z)
	w.solid(root)
	return root

## The lair's ground: a decal of its element over the terrain, fading out at the edge.
func _ground() -> Decal:
	var d := Decal.new()
	d.size = Vector3(CLEAR * 2.2, 8.0, CLEAR * 2.2)
	var tex := _ground_tex(element)
	d.texture_albedo = tex[0]
	d.texture_emission = tex[1]
	d.emission_energy = 3.0 if element != "cold" else 0.5
	d.albedo_mix = 0.92
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.cull_mask = 1
	return d

static var _tex_cache := {}

## Procedural ground textures (albedo with alpha, emission): cellular cracks over noise, a soft round edge.
static func _ground_tex(el: String) -> Array:
	if _tex_cache.has(el):
		return _tex_cache[el]
	var n := 256
	var cells := FastNoiseLite.new()
	cells.noise_type = FastNoiseLite.TYPE_CELLULAR
	cells.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cells.frequency = 0.022 if el != "lightning" else 0.016
	cells.seed = 7
	var grain := FastNoiseLite.new()
	grain.frequency = 0.05
	grain.seed = 11
	var alb := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var emi := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var u := (float(x) / n - 0.5) * 2.0
			var v := (float(y) / n - 0.5) * 2.0
			var rr := sqrt(u * u + v * v)
			var g := grain.get_noise_2d(x, y) * 0.5 + 0.5
			var edge := clampf((1.0 - rr) * 3.2 + (g - 0.5) * 1.4, 0.0, 1.0)
			# DISTANCE2_SUB is -1 on the cells' edges, rising inside them: the cracks are where it's near -1
			var crack := 1.0 - clampf((cells.get_noise_2d(x, y) + 1.0) * 7.0, 0.0, 1.0)
			crack *= smoothstep(0.95, 0.35, rr)
			match el:
				"fire":
					alb.set_pixel(x, y, Color(0.05 + 0.05 * g, 0.04 + 0.03 * g, 0.035, edge))
					# lava in the cracks, pooling bright where they're widest
					emi.set_pixel(x, y, Color(1.0, 0.32, 0.04) * pow(crack, 1.6) + Color(1.0, 0.6, 0.2) * pow(crack, 6.0))
				"cold":
					var fr := 0.78 + 0.18 * g
					alb.set_pixel(x, y, Color(fr * 0.9, fr * 0.95, fr, edge * 0.95))
					emi.set_pixel(x, y, Color(0.35, 0.6, 1.0) * crack * 0.6)
				_:
					alb.set_pixel(x, y, Color(0.12 + 0.05 * g, 0.1 + 0.04 * g, 0.15 + 0.05 * g, edge))
					emi.set_pixel(x, y, Color(0.6, 0.3, 1.0) * pow(crack, 2.2))
	_tex_cache[el] = [ImageTexture.create_from_image(alb), ImageTexture.create_from_image(emi)]
	return _tex_cache[el]

func _process(delta: float) -> void:
	_t += delta
	match element:
		"fire":
			light.light_energy = 2.2 + 0.5 * sin(_t * 7.0) + 0.25 * sin(_t * 17.0)
		"cold":
			light.light_energy = 2.0 + 0.2 * sin(_t * 0.8)
		"lightning":
			light.light_energy = move_toward(light.light_energy, 1.6, delta * 6.0)
			_bolt_t -= delta
			if _bolt_t <= 0.0 and not stones.is_empty():
				_bolt_t = randf_range(2.5, 6.0)
				var s: Node3D = stones[randi() % stones.size()]
				if is_instance_valid(s):
					var top := s.global_position + Vector3(0, 3.2, 0)
					Sloth._bolt(get_parent(), top + Vector3(randf_range(-2, 2), 16.0, randf_range(-2, 2)), top, Color(0.85, 0.7, 1.0))
					Fx.flash(get_parent(), top, Color(0.7, 0.5, 1.0), 4.0, 0.2, 8.0)
					light.light_energy = 5.0
