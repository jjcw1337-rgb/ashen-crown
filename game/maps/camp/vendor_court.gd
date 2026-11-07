extends RefCounted
## Open shop frontages: warm stone, braced oak, iron fittings and readable trade signs.
## Existing detailed workshop models form the back of each court. The middle stays walkable.
const TRADE := {"alch": "ALCHEMY", "smith": "FORGE", "armor": "ARMOURY", "gamble": "CURIOS"}
const ACCENT := {"alch": Color(0.28, 0.36, 0.17), "smith": Color(0.42, 0.16, 0.07),
	"armor": Color(0.36, 0.29, 0.17), "gamble": Color(0.35, 0.12, 0.16)}

static func build(w: World, role: String, at: Vector2, yaw: float, half: Vector2, keeper: Inter, lantern: PackedScene) -> void:
	var root := Models.N(w.props_root, "VendorCourt_" + role)
	root.position = Vector3(at.x, w.height_at(at.x, at.y), at.y)
	root.rotation.y = yaw
	var edge := half.x + 0.65
	var front := half.y + 0.85
	var stone := Mats.world(Color(0.48, 0.43, 0.33), Color(0.28, 0.25, 0.20), 0.94, 2.4, 0.08)
	var oak := Mats.world(Color(0.22, 0.14, 0.075), Color(0.15, 0.095, 0.05), 0.9, 1.0, 0.0, Color.BLACK, true, 0.0, Color.BLACK, 0.0, 1.0).duplicate() as ShaderMaterial
	# Timber uses the shared grain/occlusion shader with shallow relief, not the stone's deep bump.
	oak.shader = Mats.custom("vendor_oak", Mats.PROP_SHADER.replace("* 3.0 * (1.0 - snowc", "* 0.18 * (1.0 - snowc"))
	var iron := Mats.mat(Color(0.16, 0.15, 0.12), 0.48, 0.72)
	var brass := Mats.mat(Color(0.56, 0.39, 0.16), 0.4, 0.7)
	# Individual slabs share one draw call. Shallow edging never becomes a movement obstacle.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Geo.box(0.89, 0.12, 0.89)
	var nx := int(ceil((edge * 2.0 + 0.7) / 0.94))
	var nz := 4
	mm.instance_count = nx * nz
	var paving_rng := RandomNumberGenerator.new()
	paving_rng.seed = hash(role)
	for z in nz:
		for x in nx:
			var pos := Vector3((x - (nx - 1) * 0.5) * 0.94, 0, half.y - 0.3 + z * 0.94)
			pos.x += paving_rng.randf_range(-0.018, 0.018)
			pos.z += paving_rng.randf_range(-0.018, 0.018)
			var world_pos: Vector3 = root.transform * pos
			pos.y = w.height_at(world_pos.x, world_pos.z) - root.position.y + 0.015
			var slab_basis := Basis(Vector3.UP, paving_rng.randf_range(-0.02, 0.02))
			slab_basis = slab_basis.scaled(Vector3(paving_rng.randf_range(0.94, 1.01), 1, paving_rng.randf_range(0.94, 1.01)))
			mm.set_instance_transform(z * nx + x, Transform3D(slab_basis, pos))
	var floor := MultiMeshInstance3D.new()
	floor.multimesh = mm
	floor.material_override = stone
	floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(floor)
	# The frame brackets the workshop; no roof or counter obscures the working keeper.
	for side in [-1.0, 1.0]:
		var x: float = edge * side
		Models.P(root, Geo.box(0.65, 0.34, 0.65), stone, Vector3(x, 0.17, front))
		Models.P(root, Geo.box(0.25, 3.5, 0.25), oak, Vector3(x, 1.85, front))
		for y in [0.5, 2.8]:
			Models.P(root, Geo.box(0.29, 0.13, 0.29), iron, Vector3(x, y, front))
		Models.seg(root, Vector3(x, 2.65, front), Vector3(x - side * 0.8, 3.45, front), 0.095, 0.095, oak, 4)
		var world_post: Vector3 = root.transform * Vector3(x, 0, front)
		w.add_circle(world_post, 0.36)
		var lamp := lantern.instantiate() as Node3D
		root.add_child(lamp)
		lamp.position = Vector3(x - side * 0.35, 2.78, front + 0.1)
		Models.seg(root, Vector3(x, 3.2, front), Vector3(x - side * 0.35, 3.2, front), 0.035, 0.035, iron, 6)
		Models.seg(root, Vector3(x - side * 0.35, 3.2, front), lamp.position, 0.018, 0.018, iron, 6)
		Models.P(root, Geo.sph(0.06, 8), Mats.glow(Color(1.0, 0.77, 0.43), 3.0), lamp.position + Vector3(0, 0.24, 0))
	Models.P(root, Geo.box(edge * 2.0 + 0.4, 0.24, 0.3), oak, Vector3(0, 3.5, front))
	Models.P(root, Geo.box(2.6, 0.67, 0.16), iron, Vector3(0, 3.47, front + 0.2))
	Models.P(root, Geo.box(2.43, 0.51, 0.03), Mats.world(ACCENT[role], (ACCENT[role] as Color).darkened(0.4)), Vector3(0, 3.47, front + 0.29))
	for sx in [-1.0, 1.0]:
		Models.P(root, Geo.sph(0.055, 8), brass, Vector3(sx * 1.13, 3.47, front + 0.33))
	var sign := Label3D.new()
	sign.text = TRADE[role]
	sign.font_size = 64
	sign.pixel_size = 0.007
	sign.modulate = Color(0.95, 0.81, 0.54)
	sign.outline_size = 5
	sign.outline_modulate = Color(0.08, 0.045, 0.02)
	sign.position = Vector3(0, 3.47, front + 0.33)
	root.add_child(sign)
	# One soft neutral-warm pool per shop, rather than many shadowed point lights.
	# Low fog contribution keeps colour on faces/stone, not a competing halo in the square.
	var key := OmniLight3D.new()
	key.name = "VendorKey"
	key.light_color = Color(1.0, 0.84, 0.62)
	key.light_energy = 3.4
	key.omni_range = 7.5
	key.omni_attenuation = 1.25
	key.light_volumetric_fog_energy = 0.12
	key.shadow_enabled = false
	root.add_child(key)
	key.position = Vector3(0, 3.0, front + 0.8)
	keeper.set_meta("vendor_court", root)

static func light_captain(w: World, keeper: Inter) -> void:
	var key := OmniLight3D.new()
	key.name = "CaptainKey"
	key.light_color = Color(1.0, 0.84, 0.62)
	key.light_energy = 2.4
	key.omni_range = 5.0
	key.light_volumetric_fog_energy = 0.1
	key.shadow_enabled = false
	w.props_root.add_child(key)
	key.position = keeper.position + Vector3(0, 2.8, 1.0)
