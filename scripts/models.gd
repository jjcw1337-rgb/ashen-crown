class_name Models
extends RefCounted
## Procedural models: characters (animated rigs) and every item type.

# ---------------------------------------------------------------- helpers
static func P(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

static func N(parent: Node3D, nm: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	n.rotation_degrees = rot
	if parent:
		parent.add_child(n)
	return n

## Points a mesh's +Y axis along dir.
static func orient_y(n: Node3D, dir: Vector3) -> void:
	dir = dir.normalized()
	if dir.is_equal_approx(Vector3.UP):
		return
	if dir.is_equal_approx(Vector3.DOWN):
		n.basis = Basis(Vector3.RIGHT, PI)
		return
	n.basis = Basis(Quaternion(Vector3.UP, dir))

## A tapered limb segment from a to b (local space of parent).
static func seg(parent: Node3D, a: Vector3, b: Vector3, r0: float, r1: float, m: Material, sides := 8) -> MeshInstance3D:
	var mi := P(parent, Geo.cyl(r1, r0, a.distance_to(b), sides), m, (a + b) * 0.5)
	orient_y(mi, b - a)
	return mi

static func glass_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.85, 0.95, 0.9, 0.28)
	m.roughness = 0.05
	m.metallic_specular = 1.0
	m.rim_enabled = true
	m.rim = 0.4
	return m

## Tapered chest-to-waist torso (unit size: shoulders ~0.17 wide-radius, 0.53 tall).
static func torso_mesh() -> Mesh:
	return Geo.lathe([Vector2(0.0, -0.02), Vector2(0.135, 0.0), Vector2(0.14, 0.1), Vector2(0.155, 0.22), Vector2(0.185, 0.36), Vector2(0.19, 0.44), Vector2(0.16, 0.5), Vector2(0.07, 0.545), Vector2(0.0, 0.55)], 18, "torso")

# ---------------------------------------------------------------- humanoid rig
static func humanoid(look: Dictionary) -> Node3D:
	var h: float = look.get("height", 1.0)
	var b: float = look.get("bulk", 1.0)
	var w := h * b
	var thin: bool = look.get("thin", false)
	var skin: Color = look.get("skin", Color(0.78, 0.6, 0.48))
	var cloth: Color = look.get("cloth", Color(0.3, 0.25, 0.2))
	var cloth2: Color = look.get("cloth2", cloth.darkened(0.35))
	var rim := 0.2
	var ms := Mats.mat(skin, 0.75, 0.0, Color.BLACK, 0.0, rim)
	var mc := Mats.mat(cloth, 0.92, 0.0, Color.BLACK, 0.0, rim)
	var mc2 := Mats.mat(cloth2, 0.92, 0.0, Color.BLACK, 0.0, rim)
	var has_armor: bool = look.has("armor")
	var ma: Material = Mats.mat(look["armor"], 0.38, 0.85, Color.BLACK, 0.0, rim) if has_armor else mc
	var lr := 0.42 if thin else 1.0

	var root := Node3D.new()
	root.name = "Rig"
	var J := {}
	var hips := N(root, "hips", Vector3(0, 0.95 * h, 0))
	J["hips"] = hips
	J["hips_y"] = 0.95 * h
	# pelvis
	if thin:
		P(hips, Geo.box(0.22 * w, 0.08 * h, 0.1 * w), ms, Vector3(0, 0.0, 0))
	else:
		P(hips, Geo.box(0.32 * w, 0.17 * h, 0.2 * w), mc2, Vector3(0, -0.01 * h, 0))
	# torso
	var torso := N(hips, "torso", Vector3(0, 0.08 * h, 0))
	J["torso"] = torso
	if thin:
		seg(torso, Vector3(0, -0.06 * h, 0.02), Vector3(0, 0.56 * h, 0.02), 0.025 * w, 0.025 * w, ms)
		for i in 4:
			var rr := (0.13 - i * 0.012) * w
			P(torso, Geo.torus(rr - 0.018 * w, rr, 16, 6), ms, Vector3(0, (0.42 - i * 0.075) * h, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.72))
		P(torso, Geo.box(0.3 * w, 0.03 * h, 0.04), ms, Vector3(0, 0.47 * h, 0.02))
	else:
		P(torso, torso_mesh(), mc, Vector3(0, -0.02 * h, 0), Vector3.ZERO, Vector3(w, h, w * 0.72))
		# belt
		P(torso, Geo.torus(0.14 * w, 0.17 * w, 18, 6), Mats.mat(Color(0.2, 0.13, 0.08), 0.8), Vector3(0, -0.02 * h, 0), Vector3.ZERO, Vector3(1.0, 1.4, 0.8))
		if has_armor:
			P(torso, torso_mesh(), ma, Vector3(0, 0.1 * h, -0.004), Vector3.ZERO, Vector3(w * 1.07, h * 0.82, w * 0.8))
		if look.get("belly", false):
			P(torso, Geo.sph(0.13 * w, 12), mc, Vector3(0, 0.14 * h, -0.06 * w))
	# robe / skirt
	var robe: bool = look.get("robe", look.get("head", "") == "hood")
	if robe:
		P(hips, Geo.cyl(0.17 * w, 0.27 * w, 0.82 * h, 14), mc2, Vector3(0, -0.4 * h, 0))
	elif not thin:
		P(hips, Geo.cyl(0.165 * w, 0.21 * w, 0.24 * h, 12), mc2, Vector3(0, -0.12 * h, 0))
	# neck & head
	P(torso, Geo.cyl(0.04 * w, 0.048 * w, 0.1 * h, 8), ms, Vector3(0, 0.58 * h, 0))
	var head := N(torso, "head", Vector3(0, 0.64 * h, 0))
	J["head"] = head
	_head(head, look, h, ms, mc, mc2)
	# cape
	if look.has("cape"):
		var cm := ShaderMaterial.new()
		cm.shader = Mats.shader("cloth")
		cm.set_shader_parameter("albedo", look["cape"])
		cm.set_shader_parameter("trim", (look["cape"] as Color).lightened(0.25))
		cm.set_shader_parameter("wave", 0.6)
		var cape := P(torso, Geo.quad(0.42 * w, 0.95 * h), cm, Vector3(0, 0.08 * h, 0.13 * w), Vector3(8, 0, 0))
		cape.position.y = 0.55 * h - 0.475 * h
		J["cape"] = cape
	# arms
	for side in [1, -1]:
		var sname := "r" if side == 1 else "l"
		var sh := N(torso, "sh_" + sname, Vector3(side * 0.215 * w, 0.48 * h, 0))
		J["sh_" + sname] = sh
		P(sh, Geo.cap(0.06 * w * lr, 0.32 * h), ms if thin else mc, Vector3(0, -0.15 * h, 0))
		if has_armor:
			P(sh, Geo.sph(0.095 * w, 14, 0.5), ma, Vector3(side * 0.01, 0.0, 0), Vector3(0, 0, -side * 20), Vector3(1.0, 0.9, 1.1))
			if look.get("spikes", false):
				var sp := P(sh, Geo.cone(0.03 * w, 0.16 * h, 8), ma, Vector3(side * 0.06 * w, 0.07 * h, 0))
				sp.rotation_degrees = Vector3(0, 0, -side * 35)
		var el := N(sh, "el_" + sname, Vector3(0, -0.3 * h, 0))
		J["el_" + sname] = el
		P(el, Geo.cap(0.05 * w * lr, 0.29 * h), ms, Vector3(0, -0.135 * h, 0))
		if has_armor:
			P(el, Geo.cyl(0.058 * w, 0.064 * w, 0.14 * h, 10), ma, Vector3(0, -0.12 * h, 0))
		var hand := N(el, "hand_" + sname, Vector3(0, -0.285 * h, 0))
		J["hand_" + sname] = hand
		P(hand, Geo.sph(0.045 * w, 10), ms, Vector3(0, -0.02 * h, 0), Vector3.ZERO, Vector3(0.9, 1.3, 0.75))
		if side == 1:
			var grip := N(hand, "grip_r", Vector3(0, -0.035 * h, 0), Vector3(-28, 0, 0))
			J["grip_r"] = grip
		else:
			var grip_l := N(hand, "grip_l", Vector3(0, -0.035 * h, 0))
			J["grip_l"] = grip_l
			var mount := N(el, "mount_l", Vector3(-0.07 * w, -0.15 * h, 0), Vector3(0, 70, 0))
			J["mount_l"] = mount
	# legs
	for side in [1, -1]:
		var sname := "r" if side == 1 else "l"
		var leg := N(hips, "leg_" + sname, Vector3(side * 0.1 * w, -0.04 * h, 0))
		J["leg_" + sname] = leg
		P(leg, Geo.cap(0.075 * w * lr, 0.47 * h), ms if thin else mc2, Vector3(0, -0.22 * h, 0))
		var knee := N(leg, "knee_" + sname, Vector3(0, -0.45 * h, 0))
		J["knee_" + sname] = knee
		P(knee, Geo.cap(0.06 * w * lr, 0.44 * h), ms if thin else mc2, Vector3(0, -0.21 * h, 0))
		var boot_m: Material = ma if has_armor else Mats.mat(Color(0.18, 0.12, 0.08), 0.85)
		if not thin:
			P(knee, Geo.cyl(0.068 * w, 0.072 * w, 0.2 * h, 10), boot_m, Vector3(0, -0.3 * h, 0))
		P(knee, Geo.box(0.1 * w, 0.07 * h, 0.22 * h), ms if thin else boot_m, Vector3(0, -0.42 * h, -0.04 * h))
	# tail
	if look.get("tail", false):
		var tail := N(hips, "tail", Vector3(0, -0.05 * h, 0.1 * w))
		J["tail"] = tail
		var prev := Vector3.ZERO
		for i in 6:
			var t := float(i + 1) / 6.0
			var p := Vector3(0, -t * 0.35 * h + t * t * 0.2 * h, t * 0.7 * h)
			seg(tail, prev, p, (0.07 - i * 0.01) * w, (0.06 - i * 0.01) * w, ms)
			prev = p
	# wings
	if look.get("wings", false):
		var wm := Mats.mat(skin.darkened(0.45), 0.8, 0.0, Color.BLACK, 0.0, 0.3)
		wm = wm.duplicate()
		wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		for side in [1, -1]:
			var wing := N(torso, "wing_" + ("r" if side == 1 else "l"), Vector3(side * 0.08 * w, 0.42 * h, 0.12 * w))
			J["wing_" + ("r" if side == 1 else "l")] = wing
			var pts := PackedVector2Array([Vector2(0, 0), Vector2(0.35, 0.3), Vector2(0.75, 0.35), Vector2(0.95, 0.1), Vector2(0.8, -0.1), Vector2(0.6, -0.05), Vector2(0.5, -0.3), Vector2(0.3, -0.15), Vector2(0.15, -0.35)])
			var wmesh := Geo.extrude(pts, 0.02, "wing")
			var wi := P(wing, wmesh, wm, Vector3.ZERO, Vector3(0, -side * 30 + (180 if side == -1 else 0), 0), Vector3(0.75 * h, 0.75 * h, 1))
			wi.rotation_degrees = Vector3(0, 90 + side * -60, 0) if side == 1 else Vector3(0, -90 - 60 * side, 0)
			wi.scale = Vector3(side * 0.75 * h, 0.75 * h, 1)
			wi.rotation_degrees = Vector3(0, -20 * side, 0)
	# weapon
	if look.has("weapon"):
		var wpn := enemy_weapon(look["weapon"])
		(J["grip_r"] as Node3D).add_child(wpn)
		J["weapon"] = wpn
	root.set_meta("j", J)
	root.set_meta("h", h)
	return root

static func _eyes(head: Node3D, look: Dictionary, h: float, y: float, z: float, sp: float) -> void:
	if not look.has("eyes"):
		P(head, Geo.sph(0.012 * h, 6), Mats.mat(Color(0.05, 0.04, 0.03), 0.3), Vector3(sp * h, y * h, z * h))
		P(head, Geo.sph(0.012 * h, 6), Mats.mat(Color(0.05, 0.04, 0.03), 0.3), Vector3(-sp * h, y * h, z * h))
		return
	var em := Mats.glow(look["eyes"], 4.0)
	P(head, Geo.sph(0.016 * h, 6), em, Vector3(sp * h, y * h, z * h))
	P(head, Geo.sph(0.016 * h, 6), em, Vector3(-sp * h, y * h, z * h))

static func _head(head: Node3D, look: Dictionary, h: float, ms: Material, mc: Material, mc2: Material) -> void:
	var t: String = look.get("head", "human")
	var r := 0.11 * h
	match t:
		"skull":
			P(head, Geo.sph(r, 14), ms, Vector3(0, 0.07 * h, 0), Vector3.ZERO, Vector3(0.9, 1.0, 1.05))
			P(head, Geo.box(0.12 * h, 0.05 * h, 0.1 * h), ms, Vector3(0, -0.01 * h, -0.035 * h))
			var dark := Mats.mat(Color(0.02, 0.02, 0.02), 1.0)
			P(head, Geo.sph(0.03 * h, 8), dark, Vector3(0.04 * h, 0.07 * h, -0.085 * h))
			P(head, Geo.sph(0.03 * h, 8), dark, Vector3(-0.04 * h, 0.07 * h, -0.085 * h))
			_eyes(head, look, h, 0.07, -0.095, 0.04)
		"hood":
			P(head, Geo.sph(r * 0.9, 12), Mats.mat(Color(0.05, 0.04, 0.04), 1.0), Vector3(0, 0.06 * h, 0))
			P(head, Geo.sph(r * 1.3, 14), mc, Vector3(0, 0.08 * h, 0.06 * h), Vector3.ZERO, Vector3(1.0, 1.15, 1.0))
			P(head, Geo.cone(0.09 * h, 0.22 * h, 10), mc, Vector3(0, 0.12 * h, 0.12 * h), Vector3(-60, 0, 0))
			_eyes(head, look, h, 0.06, -0.095, 0.035)
		"mummy":
			var wrap := Mats.mat((look.get("skin", Color.WHITE) as Color), 0.95)
			P(head, Geo.sph(r, 12), wrap, Vector3(0, 0.07 * h, 0))
			for i in 4:
				P(head, Geo.torus(r * 0.95, r * 1.06, 14, 4), wrap, Vector3(0, (0.02 + i * 0.035) * h, 0), Vector3(8 - i * 5, 0, 6 - i * 3))
			_eyes(head, look, h, 0.08, -0.1, 0.035)
		"turban":
			P(head, Geo.sph(r, 12), ms, Vector3(0, 0.06 * h, 0), Vector3.ZERO, Vector3(0.92, 1.05, 1.0))
			var tm := Mats.mat(look.get("cloth", Color.WHITE), 0.95)
			P(head, Geo.sph(r * 1.2, 12), tm, Vector3(0, 0.13 * h, 0.01 * h), Vector3.ZERO, Vector3(1.0, 0.7, 1.0))
			P(head, Geo.box(0.17 * h, 0.06 * h, 0.06 * h), mc2, Vector3(0, 0.02 * h, -0.08 * h))
			_eyes(head, look, h, 0.07, -0.1, 0.035)
		"mask":
			P(head, Geo.sph(r, 12), ms, Vector3(0, 0.06 * h, 0))
			var wood := Mats.mat(Color(0.5, 0.35, 0.18), 0.8)
			var mask := P(head, Geo.box(0.2 * h, 0.28 * h, 0.04 * h), wood, Vector3(0, 0.08 * h, -0.11 * h))
			P(head, Geo.box(0.21 * h, 0.03 * h, 0.05 * h), Mats.mat(Color(0.75, 0.1, 0.05), 0.8), Vector3(0, 0.13 * h, -0.115 * h))
			P(head, Geo.box(0.12 * h, 0.03 * h, 0.05 * h), Mats.mat(Color(0.9, 0.85, 0.7), 0.8), Vector3(0, 0.0, -0.115 * h))
			for i in 5:
				var f := P(head, Geo.box(0.02 * h, 0.16 * h, 0.01 * h), Mats.mat(Color(0.8, 0.2 + i * 0.1, 0.1), 0.9), Vector3((i - 2) * 0.045 * h, 0.27 * h, -0.08 * h))
				f.rotation_degrees.z = (i - 2) * 14
			_eyes(head, look, h, 0.09, -0.135, 0.045)
			mask.name = "mask"
			if look.get("horns", false):
				_horns(head, h, Mats.mat(Color(0.85, 0.8, 0.65), 0.6), 0.9)
		"beast":
			P(head, Geo.sph(r, 12), ms, Vector3(0, 0.07 * h, 0.01 * h))
			P(head, Geo.box(0.1 * h, 0.08 * h, 0.18 * h), ms, Vector3(0, 0.035 * h, -0.1 * h))
			P(head, Geo.box(0.09 * h, 0.03 * h, 0.16 * h), ms, Vector3(0, -0.015 * h, -0.09 * h), Vector3(8, 0, 0))
			for i in 4:
				P(head, Geo.cone(0.015 * h, 0.06 * h, 5), Mats.mat((look.get("skin", Color.GREEN) as Color).lightened(0.3), 0.6), Vector3(0, (0.13 + i * 0.0) * h, (0.0 + i * 0.05) * h), Vector3(-30, 0, 0))
			_eyes(head, look, h, 0.09, -0.07, 0.055)
		"horned", "demon":
			P(head, Geo.sph(r, 12), ms, Vector3(0, 0.07 * h, 0), Vector3.ZERO, Vector3(0.95, 1.0, 1.05))
			P(head, Geo.box(0.12 * h, 0.06 * h, 0.08 * h), ms, Vector3(0, 0.0, -0.06 * h))
			_horns(head, h, Mats.mat(Color(0.12, 0.1, 0.08), 0.5), 1.4 if t == "demon" else 0.8)
			_eyes(head, look, h, 0.08, -0.095, 0.04)
		"dark_helm":
			var dm := Mats.mat(look.get("armor", Color(0.1, 0.1, 0.1)), 0.35, 0.85)
			P(head, Geo.lathe([Vector2(0.0, -0.06), Vector2(0.13, -0.05), Vector2(0.14, 0.06), Vector2(0.12, 0.15), Vector2(0.06, 0.2), Vector2(0.0, 0.21)], 16, "dhelm"), dm, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(h, h, h))
			P(head, Geo.box(0.16 * h, 0.02 * h, 0.03 * h), Mats.glow(look.get("eyes", Color.RED), 3.0), Vector3(0, 0.08 * h, -0.13 * h))
			_horns(head, h, dm, 0.7)
		"pharaoh":
			P(head, Geo.sph(r, 12), ms, Vector3(0, 0.07 * h, 0))
			var gold := Mats.mat(Color(0.9, 0.7, 0.25), 0.3, 1.0)
			var blue := Mats.mat(Color(0.08, 0.2, 0.5), 0.5, 0.3)
			for i in 7:
				P(head, Geo.box(0.26 * h, 0.035 * h, 0.2 * h), gold if i % 2 == 0 else blue, Vector3(0, (0.02 + i * 0.03) * h, 0.03 * h), Vector3(0, 0, 0), Vector3(1.0 - i * 0.07, 1, 1))
			for side in [1, -1]:
				P(head, Geo.box(0.06 * h, 0.22 * h, 0.12 * h), gold, Vector3(side * 0.12 * h, -0.05 * h, 0.03 * h))
			P(head, Geo.cyl(0.015 * h, 0.02 * h, 0.08 * h, 6), gold, Vector3(0, 0.2 * h, -0.08 * h), Vector3(-20, 0, 0))
			_eyes(head, look, h, 0.08, -0.1, 0.04)
		_:
			P(head, Geo.sph(r, 14), ms, Vector3(0, 0.07 * h, 0), Vector3.ZERO, Vector3(0.9, 1.05, 1.0))
			P(head, Geo.box(0.022 * h, 0.04 * h, 0.03 * h), ms, Vector3(0, 0.06 * h, -0.105 * h))
			if look.has("hair"):
				P(head, Geo.sph(r * 1.06, 14, 0.5), Mats.mat(look["hair"], 0.9), Vector3(0, 0.085 * h, 0.012 * h), Vector3(-12, 0, 0))
			if look.has("beard"):
				P(head, Geo.cone(0.07 * h, 0.13 * h, 10), Mats.mat(look["beard"], 0.95), Vector3(0, -0.01 * h, -0.07 * h), Vector3(180 - 15, 0, 0))
			_eyes(head, look, h, 0.085, -0.095, 0.037)

static func _horns(head: Node3D, h: float, m: Material, size: float) -> void:
	for side in [1, -1]:
		var prev := Vector3(side * 0.08 * h, 0.13 * h, -0.01 * h)
		var dir := Vector3(side * 0.7, 0.75, 0.15).normalized()
		var r := 0.035 * h * size
		for i in 5:
			var nxt := prev + dir * 0.06 * h * size
			seg(head, prev, nxt, r, r * 0.75, m, 7)
			prev = nxt
			r *= 0.75
			dir = (dir + Vector3(side * 0.1, -0.12, -0.25)).normalized()

# ---------------------------------------------------------------- crawler rig (spiders, beetles)
static func crawler(look: Dictionary) -> Node3D:
	var s: float = look.get("size", 1.0)
	var skin: Color = look.get("skin", Color(0.1, 0.1, 0.1))
	var shell: Color = look.get("shell", skin)
	var n: int = look.get("legs", 8)
	var ms := Mats.mat(skin, 0.6, 0.1, Color.BLACK, 0.0, 0.25)
	var mshell := Mats.mat(shell, 0.25, 0.55, Color.BLACK, 0.0, 0.35)
	var root := Node3D.new()
	root.name = "Rig"
	var J := {}
	var body := N(root, "body", Vector3(0, 0.45 * s, 0))
	J["body"] = body
	J["body_y"] = 0.45 * s
	P(body, Geo.sph(0.26 * s, 16), ms, Vector3(0, 0, -0.1 * s), Vector3.ZERO, Vector3(1.0, 0.7, 1.1))
	if n == 8:
		P(body, Geo.sph(0.38 * s, 18), mshell, Vector3(0, 0.12 * s, 0.38 * s), Vector3.ZERO, Vector3(1.0, 0.85, 1.2))
		if look.has("stripe"):
			var stm := Mats.mat(look["stripe"], 0.5)
			for i in 3:
				P(body, Geo.torus(0.25 * s - i * 0.04 * s, 0.29 * s - i * 0.04 * s, 18, 4), stm, Vector3(0, (0.33 - i * 0.03) * s, (0.25 + i * 0.12) * s), Vector3(-40 - i * 10, 0, 0), Vector3(1.0, 1.0, 1.0))
	else:
		P(body, Geo.sph(0.4 * s, 18, 0.5), mshell, Vector3(0, -0.02 * s, 0.2 * s), Vector3.ZERO, Vector3(1.0, 0.75, 1.35))
		P(body, Geo.box(0.02 * s, 0.05 * s, 0.9 * s), Mats.mat(shell.darkened(0.5), 0.4, 0.5), Vector3(0, 0.28 * s, 0.2 * s))
		if look.get("horn", false):
			P(body, Geo.cone(0.05 * s, 0.35 * s, 8), mshell, Vector3(0, 0.08 * s, -0.4 * s), Vector3(-65, 0, 0))
	# eyes & mandibles
	if look.has("eyes"):
		var em := Mats.glow(look["eyes"], 4.0)
		for i in (4 if n == 8 else 2):
			var ex := (float(i % 2) - 0.5) * 0.12 * s * (1.0 + float(i / 2) * 0.6)
			P(body, Geo.sph(0.025 * s, 6), em, Vector3(ex, 0.08 * s + (i / 2) * 0.04 * s, -0.33 * s))
	for side in [1, -1]:
		var md := N(body, "mand_" + str(side), Vector3(side * 0.06 * s, -0.05 * s, -0.33 * s))
		seg(md, Vector3.ZERO, Vector3(-side * 0.04 * s, -0.08 * s, -0.08 * s), 0.025 * s, 0.006 * s, ms, 6)
		J["mand_" + str(side)] = md
	# legs
	var legs := []
	for i in n:
		var side := 1 if i < n / 2 else -1
		var k := i % (n / 2)
		var zf := lerpf(-0.2, 0.2, float(k) / max(1, n / 2 - 1)) * s
		var hip := N(body, "hip%d" % i, Vector3(side * 0.18 * s, 0.0, zf))
		hip.rotation.y = side * (-0.5 + float(k) / max(1, n / 2 - 1)) * 0.9 + (PI if side == -1 else 0.0)
		var up := Vector3(0.45 * s, 0.25 * s, 0)
		seg(hip, Vector3.ZERO, up, 0.04 * s, 0.03 * s, ms, 6)
		var knee := N(hip, "knee", up)
		seg(knee, Vector3.ZERO, Vector3(0.3 * s, -0.72 * s, 0), 0.03 * s, 0.01 * s, ms, 6)
		legs.append({"hip": hip, "knee": knee, "base_y": hip.rotation.y, "phase": (0.0 if (k + (1 if side == -1 else 0)) % 2 == 0 else PI), "side": side})
	J["legs"] = legs
	root.set_meta("j", J)
	root.set_meta("h", s)
	root.set_meta("crawler", true)
	return root

# ---------------------------------------------------------------- palettes
static func palette(item: Dictionary) -> Dictionary:
	var r: int = item.get("rarity", 0)
	var p := {
		"metal": Color(0.6, 0.6, 0.62), "dark": Color(0.18, 0.17, 0.17), "wood": Color(0.34, 0.21, 0.11),
		"leather": Color(0.32, 0.2, 0.12), "trim": Color(0.48, 0.44, 0.38), "cloth": Color(0.45, 0.12, 0.08),
		"gem": null, "glow": null,
	}
	if r == 1:
		p["metal"] = Color(0.6, 0.65, 0.76)
		p["trim"] = Color(0.45, 0.55, 0.85)
		p["gem"] = Color(0.25, 0.45, 1.0)
		p["cloth"] = Color(0.12, 0.2, 0.5)
	elif r == 2:
		p["metal"] = Color(0.68, 0.66, 0.6)
		p["trim"] = Color(0.88, 0.68, 0.28)
		p["gem"] = Color(1.0, 0.75, 0.15)
		p["cloth"] = Color(0.5, 0.35, 0.08)
	elif r == 3 and Data.UNIQUES.has(item.get("unique", "")):
		var u: Dictionary = Data.UNIQUES[item["unique"]]
		p["metal"] = u["metal"]
		p["trim"] = u["trim"]
		p["gem"] = u["gem"]
		p["glow"] = u["glow"]
		p["cloth"] = (u["trim"] as Color).darkened(0.4)
		p["leather"] = (u["metal"] as Color).darkened(0.3)
	if int(item.get("ench", 0)) >= 5 and p["glow"] == null:
		# well-enchanted gear picks up a faint arcane glow
		p["glow"] = Color(0.4, 0.58, 1.0)
		p["gem"] = Color(0.45, 0.65, 1.0) if p["gem"] == null else p["gem"]
	return p

static func _metal(p: Dictionary) -> Material:
	if p["glow"] != null:
		return Mats.mat(p["metal"], 0.3, 0.9, p["glow"], 0.35)
	return Mats.mat(p["metal"], 0.3, 0.92)

static func _trim(p: Dictionary) -> Material:
	return Mats.mat(p["trim"], 0.28, 0.95)

static func _gem(p: Dictionary) -> Material:
	return Mats.mat(p["gem"], 0.1, 0.2, p["gem"], 2.5)

# ---------------------------------------------------------------- item models
## Returns a model for an item. Weapons: grip at origin, blade along -Z.
## Shields face -Z. Helms are centred on the head. Others are free-standing.
const RANGER_BOW := "res://assets/models/ranger_bow.glb"

static func item_model(item: Dictionary) -> Node3D:
	var base: Dictionary = Data.BASES[item["base"]]
	var p := palette(item)
	var kind: String = base["kind"]
	var sh: Dictionary = base.get("shape", {})
	match base["slot"]:
		"weapon":
			# bows (the archer's): the bow geometry the skeleton archers carry (weapon() has no bow of its own)
			if kind in ["bow", "longbow"]:
				# the ranger's own carved recurve (Meshy, tools/blender/archer/prep_bow.py) when it's there; a
				# longbow is the same bow drawn longer
				if ResourceLoader.exists(RANGER_BOW):
					var b: Node3D = (load(RANGER_BOW) as PackedScene).instantiate()
					var root := Node3D.new()
					root.add_child(b)
					b.scale = Vector3.ONE * (1.15 if kind == "longbow" else 1.0)
					root.set_meta("ranger_bow", true)
					return root
				return enemy_weapon(kind)
			return weapon(kind, sh, p)
		"shield": return shield(kind, sh, p)
		"helm": return helm(kind, p)
		"armor": return armor_item(kind, p)
		"gloves": return gloves(kind, p)
		"boots": return boots(kind, p)
		"belt": return belt(kind, p)
		"ring": return ring(p)
		"amulet": return amulet(p)
		"potion": return potion(base["color"], item["base"])
		"gold": return gold_pile(item.get("count", 50))
		"material": return material(item["base"])
	return Node3D.new()

## A Hollow Sloth's material: its Meshy model (assets/models/items/<id>.glb, about 0.3 m) or, without
## it, a glowing stand-in of its kind; either way lit from inside in its colour.
static func material(id: String) -> Node3D:
	var b: Dictionary = Data.BASES[id]
	var col: Color = b["color"]
	var root := Node3D.new()
	if b.has("model") and ResourceLoader.exists(b["model"]):
		var m: Node3D = (load(b["model"]) as PackedScene).instantiate()
		root.add_child(m)
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = Mats.glow(col, 0.5, 0.0, 1.0)
	else:
		match b["kind"]:
			"ember":
				P(root, SphereMesh.new(), Mats.mat(Color(0.08, 0.06, 0.05), 0.9, 0.0, col, 0.8), Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(0.24, 0.22, 0.2))
			"talon":
				var c := CylinderMesh.new()
				c.top_radius = 0.0
				c.bottom_radius = 0.05
				c.height = 0.36
				P(root, c, Mats.mat(col.lerp(Color.WHITE, 0.4), 0.1, 0.0, col, 1.2), Vector3(0, 0.15, 0), Vector3(0, 0, 25))
			_:
				P(root, SphereMesh.new(), Mats.mat(col.darkened(0.4), 0.05, 0.0, col, 1.6), Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(0.2, 0.2, 0.2))
	# the glow inside it
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.06
	sm.height = 0.12
	core.mesh = sm
	core.material_override = Mats.glow(col, 3.0, 0.0, 0.0)
	core.position = Vector3(0, 0.12, 0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	return root

static func weapon(kind: String, sh: Dictionary, p: Dictionary) -> Node3D:
	if kind == "bow":
		# the archer's bows: the hunting longbow, held in the left hand (Hero.refresh_gear)
		return enemy_weapon("longbow")
	var root := Node3D.new()
	var w := N(root, "w", Vector3.ZERO, Vector3(-90, 0, 0))
	var mm := _metal(p)
	var mt := _trim(p)
	var mw := Mats.mat(p["wood"], 0.85)
	var ml := Mats.mat(p["leather"], 0.8)
	match kind:
		"sword":
			var L: float = sh.get("len", 0.7)
			var W: float = sh.get("w", 0.07)
			var G: float = sh.get("guard", 0.22)
			P(w, Geo.cyl(0.017, 0.02, 0.17, 10), ml, Vector3(0, -0.02, 0))
			for i in 3:
				P(w, Geo.torus(0.015, 0.023, 12, 5), mt, Vector3(0, -0.08 + i * 0.055, 0))
			P(w, Geo.sph(0.03, 10), mt, Vector3(0, -0.125, 0))
			var gpts := PackedVector2Array([Vector2(-G * 0.5, -0.012), Vector2(-G * 0.42, 0.02), Vector2(0, 0.03), Vector2(G * 0.42, 0.02), Vector2(G * 0.5, -0.012), Vector2(G * 0.4, -0.02), Vector2(0, -0.018), Vector2(-G * 0.4, -0.02)])
			P(w, Geo.extrude(gpts, 0.045, "guard%.3f" % G), mt, Vector3(0, 0.075, 0))
			P(w, Geo.sph(0.022, 8), mt, Vector3(G * 0.5, 0.068, 0))
			P(w, Geo.sph(0.022, 8), mt, Vector3(-G * 0.5, 0.068, 0))
			if p["gem"] != null:
				P(w, Geo.sph(0.017, 8), _gem(p), Vector3(0, 0.08, -0.022))
				P(w, Geo.sph(0.017, 8), _gem(p), Vector3(0, 0.08, 0.022))
			var curve: float = sh.get("curve", 0.0)
			var wavy: float = sh.get("wavy", 0.0)
			var pts := PackedVector2Array()
			var n := 14
			var right := []
			var left := []
			for i in n:
				var t := float(i) / n
				var y := 0.09 + t * L * 0.9
				var off := curve * W * 1.4 * t * t
				var hw := W * 0.5 * (1.0 - t * 0.3)
				if curve > 0.0:
					hw = W * 0.5 * (0.8 + sin(t * PI) * 0.45)
				if wavy > 0.0:
					hw += sin(t * PI * 7.0) * W * 0.12
				right.append(Vector2(off + hw, y))
				left.append(Vector2(off - hw * (0.6 if curve > 0.0 else 1.0), y))
			for v in right:
				pts.append(v)
			pts.append(Vector2(curve * W * 1.6, 0.09 + L))
			for i in range(left.size() - 1, -1, -1):
				pts.append(left[i])
			var bm := Geo.extrude(pts, 0.014, "blade%.3f%.3f%.2f%.2f" % [L, W, curve, wavy])
			P(w, bm, mm)
			P(w, Geo.box(W * 0.18, L * 0.72, 0.018), Mats.mat((p["metal"] as Color).darkened(0.3), 0.35, 0.9), Vector3(curve * W * 0.3, 0.09 + L * 0.4, 0))
			if sh.get("runes", 0.0) > 0.0 or p["glow"] != null:
				var gc: Color = p["glow"] if p["glow"] != null else Color(0.4, 0.7, 1.0)
				for i in 5:
					P(w, Geo.box(W * 0.25, 0.03, 0.02), Mats.glow(gc, 3.0), Vector3(curve * W * 0.3, 0.16 + i * L * 0.13, 0))
		"axe":
			var H: float = sh.get("haft", 0.65)
			var hs: float = sh.get("head", 0.2)
			P(w, Geo.cyl(0.021, 0.025, H, 10), mw, Vector3(0, H * 0.5 - 0.15, 0))
			P(w, Geo.cyl(0.026, 0.026, 0.12, 10), ml, Vector3(0, -0.06, 0))
			var top := H - 0.15
			P(w, Geo.cyl(0.035, 0.035, 0.13, 10), mm, Vector3(0, top - 0.09, 0))
			var beard: float = sh.get("beard", 0.0)
			var apts := PackedVector2Array([Vector2(0.02, -0.04), Vector2(hs * 0.45, -0.06 - beard * hs * 0.3), Vector2(hs * 0.9, -hs * 0.55 - beard * hs * 0.4), Vector2(hs * 1.05, -hs * 0.2), Vector2(hs * 1.08, hs * 0.1), Vector2(hs * 0.95, hs * 0.45), Vector2(hs * 0.45, hs * 0.12), Vector2(0.02, 0.05)])
			var am := Geo.extrude(apts, 0.028, "axe%.3f%.2f" % [hs, beard])
			P(w, am, mm, Vector3(0, top - 0.09, 0))
			P(w, Geo.box(hs * 0.12, hs * 0.9, 0.03), Mats.mat((p["metal"] as Color).lightened(0.25), 0.15, 1.0), Vector3(hs * 1.0, top - 0.09 - hs * 0.06, 0))
			if sh.get("double", 0.0) > 0.0:
				P(w, am, mm, Vector3(0, top - 0.09, 0), Vector3(0, 180, 0))
			else:
				P(w, Geo.prism(0.1, 0.06, 0.03), mm, Vector3(-0.07, top - 0.09, 0), Vector3(0, 0, 90))
			P(w, Geo.cone(0.02, 0.09, 8), mt, Vector3(0, top + 0.01, 0))
			if p["gem"] != null:
				P(w, Geo.sph(0.02, 8), _gem(p), Vector3(0.0, top - 0.09, -0.03))
		"club":
			var L2: float = sh.get("len", 0.6)
			P(w, Geo.cyl(0.055, 0.022, L2, 9), mw, Vector3(0, L2 * 0.5 - 0.12, 0))
			for i in 7:
				var a := i * 2.4
				var ny := 0.18 + (i % 3) * 0.08
				var nail := P(w, Geo.cone(0.012, 0.07, 5), Mats.mat(Color(0.35, 0.33, 0.3), 0.5, 0.8), Vector3(cos(a) * 0.045, ny + 0.05, sin(a) * 0.045))
				orient_y(nail, Vector3(cos(a), 0.1, sin(a)))
		"mace", "star", "hammer":
			var L3: float = sh.get("len", 0.62)
			P(w, Geo.cyl(0.019, 0.022, L3, 10), mw if kind != "hammer" else mm, Vector3(0, L3 * 0.5 - 0.13, 0))
			P(w, Geo.cyl(0.024, 0.024, 0.14, 10), ml, Vector3(0, -0.05, 0))
			P(w, Geo.sph(0.028, 8), mt, Vector3(0, -0.13, 0))
			var top3 := L3 - 0.13
			if kind == "mace":
				P(w, Geo.sph(0.055, 12), mm, Vector3(0, top3, 0))
				var fl: int = sh.get("flanges", 6)
				for i in fl:
					var a := TAU * i / fl
					P(w, Geo.prism(0.07, 0.16, 0.014), mm, Vector3(cos(a) * 0.05, top3, sin(a) * 0.05), Vector3(0, -rad_to_deg(a), -90))
			elif kind == "star":
				P(w, Geo.torus(0.012, 0.022, 10, 5), mt, Vector3(0, top3 + 0.03, 0), Vector3(90, 0, 0))
				P(w, Geo.torus(0.012, 0.022, 10, 5), mt, Vector3(0, top3 + 0.065, 0))
				var c := Vector3(0, top3 + 0.17, 0)
				P(w, Geo.sph(0.075, 14), mm, c)
				for i in 14:
					var yy := 1.0 - (i + 0.5) / 14.0 * 2.0
					var rr := sqrt(1.0 - yy * yy)
					var a := i * 2.399963
					var d := Vector3(cos(a) * rr, yy, sin(a) * rr)
					var sp := P(w, Geo.cone(0.018, 0.08, 6), mm, c + d * 0.09)
					orient_y(sp, d)
			else:
				P(w, Geo.box(0.22, 0.085, 0.085), mm, Vector3(0.0, top3, 0))
				P(w, Geo.box(0.03, 0.1, 0.1), mt, Vector3(0.1, top3, 0))
				P(w, Geo.box(0.03, 0.1, 0.1), mt, Vector3(-0.1, top3, 0))
				var spk := P(w, Geo.cone(0.03, 0.12, 6), mm, Vector3(-0.17, top3, 0))
				spk.rotation_degrees = Vector3(0, 0, 90)
				P(w, Geo.cone(0.025, 0.1, 6), mm, Vector3(0, top3 + 0.09, 0))
			if p["gem"] != null:
				P(w, Geo.sph(0.018, 8), _gem(p), Vector3(0, top3 - 0.06, -0.02))
	return root

## Non-item weapons carried by monsters.
static func enemy_weapon(kind: String) -> Node3D:
	var p := palette({"rarity": 0})
	match kind:
		"club": return weapon("club", {"len": 0.55}, p)
		"scimitar":
			p["metal"] = Color(0.7, 0.68, 0.6)
			return weapon("sword", {"len": 0.7, "w": 0.08, "guard": 0.16, "curve": 1.2}, p)
		"great_sword":
			p["metal"] = Color(0.18, 0.16, 0.16)
			p["glow"] = Color(1.0, 0.25, 0.05)
			p["gem"] = Color(1.0, 0.2, 0.05)
			return weapon("sword", {"len": 1.15, "w": 0.13, "guard": 0.4, "wavy": 1.0}, p)
		"sickle":
			# the Fallen Skirmisher's hooked blade
			p["metal"] = Color(0.42, 0.36, 0.3)
			return weapon("sword", {"len": 0.5, "w": 0.06, "guard": 0.06, "curve": 3.0}, p)
		"cleaver":
			# the Fallen Reaver's cleaver-axe: a short haft and one broad, chipped head
			p["metal"] = Color(0.5, 0.46, 0.42)
			return weapon("axe", {"haft": 0.8, "head": 0.5, "beard": 1.0}, p)
		"great_axe":
			p["metal"] = Color(0.2, 0.15, 0.13)
			p["glow"] = Color(1.0, 0.35, 0.05)
			p["gem"] = Color(1.0, 0.4, 0.05)
			return weapon("axe", {"haft": 1.3, "head": 0.45, "double": 1.0, "beard": 1.0}, p)
	var root := Node3D.new()
	var wood := Mats.mat(Color(0.3, 0.2, 0.1), 0.85)
	match kind:
		"bow":
			var prev := Vector3(0, 0, -0.55)
			for i in 10:
				var t := float(i + 1) / 10.0
				var z := lerpf(-0.55, 0.55, t)
				var nx := Vector3(0.0 + 0.18 * (1.0 - pow(2.0 * t - 1.0, 2.0)), 0, z)
				seg(root, prev, nx, 0.018, 0.018, wood, 6)
				prev = nx
			var bstr := seg(root, Vector3(0, 0, -0.55), Vector3(0, 0, 0.55), 0.003, 0.003, Mats.mat(Color(0.85, 0.8, 0.7), 0.6), 4)
			bstr.name = "string"
			root.rotation_degrees = Vector3(0, 0, 0)
			root.position = Vector3(0, 0, 0)
		"longbow":
			var lw := Mats.mat(Color(0.33, 0.2, 0.11), 0.75)
			var pts := []
			for i in 15:
				var t := float(i) / 14.0
				var y := lerpf(-0.82, 0.86, t)
				var u := y / 0.84
				var z := -0.11 * (1.0 - u * u) + 0.05 * pow(absf(u), 6.0)
				pts.append(Vector3(0, y, z))
			for i in pts.size() - 1:
				var tt := float(i) / (pts.size() - 1)
				var r := lerpf(0.016, 0.01, absf(tt - 0.5) * 2.0)
				seg(root, pts[i], pts[i + 1], r * 1.1, r, lw, 7)
			for k in 6:
				P(root, Geo.torus(0.015, 0.023, 10, 4), Mats.mat(Color(0.22, 0.14, 0.08), 0.9), Vector3(0, -0.06 + k * 0.022, -0.11))
			for e in [pts[0], pts[pts.size() - 1]]:
				P(root, Geo.sph(0.016, 6), Mats.mat(Color(0.5, 0.45, 0.38), 0.6), e)
			var string := seg(root, pts[0], pts[pts.size() - 1], 0.003, 0.003, Mats.mat(Color(0.8, 0.75, 0.62), 0.7), 4)
			string.name = "string"
			root.position = Vector3(0, 0.0, 0.11)
		"spear":
			seg(root, Vector3(0, 0, 0.6), Vector3(0, 0, -1.1), 0.02, 0.02, wood, 8)
			var bp := PackedVector2Array([Vector2(0, 0), Vector2(0.05, 0.08), Vector2(0.035, 0.22), Vector2(0, 0.3), Vector2(-0.035, 0.22), Vector2(-0.05, 0.08)])
			P(root, Geo.extrude(bp, 0.015, "spearhead"), Mats.mat(Color(0.55, 0.55, 0.5), 0.35, 0.9), Vector3(0, 0, -1.1), Vector3(-90, 0, 0))
			P(root, Geo.torus(0.018, 0.03, 10, 5), Mats.mat(Color(0.6, 0.2, 0.1), 0.9), Vector3(0, 0, -1.05), Vector3(90, 0, 0))
		"staff":
			seg(root, Vector3(0, -0.7, 0), Vector3(0, 0.9, 0), 0.025, 0.02, wood, 8)
			P(root, Geo.sph(0.07, 12), Mats.glow(Color(1.0, 0.45, 0.1), 3.0), Vector3(0, 0.98, 0))
			for i in 3:
				var a := TAU * i / 3.0
				var cl := seg(root, Vector3(0, 0.88, 0), Vector3(cos(a) * 0.08, 1.05, sin(a) * 0.08), 0.012, 0.006, wood, 5)
				cl.name = "claw%d" % i
			root.rotation_degrees = Vector3(28, 0, 0)
		"scythe":
			seg(root, Vector3(0, -0.9, 0), Vector3(0, 1.3, 0), 0.025, 0.022, Mats.mat(Color(0.15, 0.12, 0.1), 0.8), 8)
			var sp := PackedVector2Array()
			for i in 13:
				var t := float(i) / 12.0
				sp.append(Vector2(-t * 0.9, sin(t * PI * 0.5) * 0.12 - t * t * 0.25))
			for i in range(12, -1, -1):
				var t := float(i) / 12.0
				sp.append(Vector2(-t * 0.9, sin(t * PI * 0.5) * 0.12 - t * t * 0.25 - 0.13 * (1.0 - t)))
			P(root, Geo.extrude(sp, 0.012, "scythe"), Mats.mat(Color(0.4, 0.42, 0.45), 0.3, 0.9), Vector3(0, 1.25, 0), Vector3(0, 90, 0))
			root.rotation_degrees = Vector3(28, 0, 0)
		"blowgun":
			seg(root, Vector3(0, 0, 0.2), Vector3(0, 0, -0.75), 0.018, 0.014, Mats.mat(Color(0.5, 0.55, 0.25), 0.7), 6)
	return root

static func shield(kind: String, sh: Dictionary, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mm := _metal(p)
	var mt := _trim(p)
	var mw := Mats.mat(p["wood"], 0.85)
	match kind:
		"round", "spiked":
			var r: float = sh.get("r", 0.2)
			P(root, Geo.cyl(r, r, 0.035, 28), mw if kind == "round" else mm, Vector3.ZERO, Vector3(90, 0, 0))
			if kind == "round":
				for i in 4:
					P(root, Geo.box(0.008, r * 1.9, 0.004), Mats.mat((p["wood"] as Color).darkened(0.4), 0.9), Vector3((i - 1.5) * r * 0.45, 0, -0.019))
			P(root, Geo.torus(r - 0.015, r + 0.01, 32, 6), mt, Vector3.ZERO, Vector3(90, 0, 0))
			P(root, Geo.sph(r * 0.3, 14, 0.5), mm if kind == "round" else mt, Vector3(0, 0, -0.017), Vector3(-90, 0, 0))
			if kind == "spiked":
				P(root, Geo.torus(r * 0.55, r * 0.6, 24, 4), mt, Vector3(0, 0, -0.02), Vector3(90, 0, 0))
				for i in 8:
					var a := TAU * i / 8.0
					var spk := P(root, Geo.cone(0.022, 0.09, 6), mm, Vector3(cos(a) * r * 0.75, sin(a) * r * 0.75, -0.05))
					spk.rotation_degrees = Vector3(-90, 0, 0)
				var c := P(root, Geo.cone(0.035, 0.18, 8), mm, Vector3(0, 0, -0.14))
				c.rotation_degrees = Vector3(-90, 0, 0)
			if p["gem"] != null:
				P(root, Geo.sph(0.03, 8), _gem(p), Vector3(0, 0, -r * 0.3 - 0.01))
		"kite", "aegis":
			var W: float = sh.get("w", 0.42)
			var H: float = sh.get("h", 0.64)
			var pts := PackedVector2Array()
			var n := 10
			for i in n + 1:
				var x := lerpf(-W * 0.5, W * 0.5, float(i) / n)
				pts.append(Vector2(x, H * 0.3 + H * 0.06 * (1.0 - pow(x / (W * 0.5), 2.0))))
			for i in range(1, n + 1):
				var t := float(i) / n
				pts.append(Vector2(W * 0.5 * (1.0 - pow(t, 1.6)), H * 0.3 - t * H))
			for i in range(n - 1, 0, -1):
				var t := float(i) / n
				pts.append(Vector2(-W * 0.5 * (1.0 - pow(t, 1.6)), H * 0.3 - t * H))
			var face := Geo.extrude(pts, 0.035, "kite%.2f%.2f" % [W, H])
			P(root, face, mm if kind == "aegis" else Mats.mat(p["cloth"], 0.7), Vector3(0, 0.1, 0))
			P(root, face, mt, Vector3(0, 0.1, 0.012), Vector3.ZERO, Vector3(1.08, 1.06, 1.0))
			if kind == "kite":
				P(root, Geo.box(0.05, H * 0.75, 0.01), mt, Vector3(0, 0.05, -0.02))
				P(root, Geo.box(W * 0.75, 0.05, 0.01), mt, Vector3(0, 0.22, -0.02))
			else:
				for i in 12:
					var a := TAU * i / 12.0
					var ray := P(root, Geo.prism(0.05, 0.16, 0.012), mt, Vector3(cos(a) * 0.1, 0.15 + sin(a) * 0.1, -0.02))
					ray.rotation = Vector3(0, 0, a - PI * 0.5)
				P(root, Geo.sph(0.06, 14, 0.5), mt, Vector3(0, 0.15, -0.02), Vector3(-90, 0, 0))
			if p["gem"] != null:
				P(root, Geo.sph(0.03, 8), _gem(p), Vector3(0, 0.22 if kind == "kite" else 0.15, -0.05))
		"tower":
			var W2: float = sh.get("w", 0.5)
			var H2: float = sh.get("h", 0.86)
			var pts2 := PackedVector2Array()
			var rr := 0.08
			var corners := [Vector2(W2 * 0.5 - rr, H2 * 0.5 - rr), Vector2(-W2 * 0.5 + rr, H2 * 0.5 - rr), Vector2(-W2 * 0.5 + rr, -H2 * 0.5 + rr), Vector2(W2 * 0.5 - rr, -H2 * 0.5 + rr)]
			for c in 4:
				for k in 5:
					var a := PI * 0.5 * c + PI * 0.5 * k / 4.0
					pts2.append(corners[c] + Vector2(cos(a), sin(a)) * rr)
			var tf := Geo.extrude(pts2, 0.045, "tower%.2f%.2f" % [W2, H2])
			P(root, tf, Mats.mat(p["wood"], 0.8))
			P(root, tf, mt, Vector3(0, 0, 0.012), Vector3.ZERO, Vector3(1.06, 1.04, 1.0))
			for i in 3:
				P(root, Geo.box(0.06, H2 * 0.96, 0.012), mm, Vector3((i - 1) * W2 * 0.33, 0, -0.026))
			P(root, Geo.box(W2 * 0.95, 0.06, 0.012), mm, Vector3(0, H2 * 0.25, -0.028))
			P(root, Geo.box(W2 * 0.95, 0.06, 0.012), mm, Vector3(0, -H2 * 0.25, -0.028))
			for i in 3:
				for j in 2:
					P(root, Geo.sph(0.014, 6), mt, Vector3((i - 1) * W2 * 0.33, (j * 2 - 1) * H2 * 0.25, -0.035))
			if p["gem"] != null:
				P(root, Geo.sph(0.035, 8), _gem(p), Vector3(0, 0, -0.04))
	return root

static func helm(kind: String, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mm := _metal(p)
	var mt := _trim(p)
	match kind:
		"cap":
			var lm := Mats.mat(p["leather"], 0.85)
			P(root, Geo.sph(0.128, 16, 0.5), lm, Vector3(0, 0.035, 0.0), Vector3.ZERO, Vector3(1.0, 0.95, 1.06))
			P(root, Geo.torus(0.12, 0.138, 22, 5), Mats.mat((p["leather"] as Color).darkened(0.35), 0.8), Vector3(0, 0.04, 0))
			for i in 4:
				P(root, Geo.box(0.012, 0.012, 0.25), Mats.mat((p["leather"] as Color).darkened(0.3), 0.8), Vector3(0, 0.16, 0), Vector3(0, i * 45, 0))
		"skullcap":
			P(root, Geo.lathe([Vector2(0.14, -0.005), Vector2(0.142, 0.05), Vector2(0.13, 0.1), Vector2(0.1, 0.145), Vector2(0.05, 0.17), Vector2(0.0, 0.175)], 20, "skullcap"), mm)
			P(root, Geo.torus(0.135, 0.152, 24, 5), mt, Vector3(0, 0.005, 0))
			P(root, Geo.box(0.024, 0.11, 0.014), mt, Vector3(0, -0.035, -0.148))
			P(root, Geo.box(0.02, 0.012, 0.3), mt, Vector3(0, 0.168, 0), Vector3(-5, 0, 0))
		"great":
			P(root, Geo.lathe([Vector2(0.15, -0.15), Vector2(0.152, -0.02), Vector2(0.148, 0.08), Vector2(0.13, 0.14), Vector2(0.06, 0.17), Vector2(0.0, 0.172)], 20, "greathelm"), mm)
			P(root, Geo.box(0.17, 0.02, 0.03), Mats.mat(Color(0.01, 0.01, 0.01), 1.0), Vector3(0, 0.03, -0.142))
			P(root, Geo.box(0.03, 0.26, 0.02), mt, Vector3(0, -0.01, -0.152))
			P(root, Geo.torus(0.145, 0.16, 24, 4), mt, Vector3(0, 0.08, 0))
			for i in 6:
				P(root, Geo.sph(0.007, 4), Mats.mat(Color(0.01, 0.01, 0.01), 1.0), Vector3(0.03 + (i % 3) * 0.022, -0.06 - (i / 3) * 0.025, -0.148))
			P(root, Geo.box(0.02, 0.06, 0.24), mt, Vector3(0, 0.18, 0.0))
		"horned":
			P(root, Geo.lathe([Vector2(0.145, -0.03), Vector2(0.147, 0.05), Vector2(0.135, 0.1), Vector2(0.1, 0.15), Vector2(0.05, 0.175), Vector2(0.0, 0.18)], 20, "hornhelm"), mm)
			P(root, Geo.torus(0.14, 0.158, 24, 5), mt, Vector3(0, -0.02, 0))
			P(root, Geo.box(0.11, 0.09, 0.02), mm, Vector3(0, -0.05, -0.145))
			P(root, Geo.box(0.12, 0.015, 0.03), Mats.mat(Color(0.01, 0.01, 0.01), 1.0), Vector3(0, -0.02, -0.15))
			var hm := Mats.mat(Color(0.85, 0.8, 0.65), 0.5)
			for side in [1, -1]:
				var prev := Vector3(side * 0.13, 0.06, 0)
				var dir := Vector3(side, 0.35, -0.2).normalized()
				var r := 0.04
				for i in 6:
					var nx := prev + dir * 0.06
					seg(root, prev, nx, r, r * 0.78, hm, 8)
					prev = nx
					r *= 0.78
					dir = (dir + Vector3(0, 0.35, -0.12)).normalized()
		"crown":
			P(root, Geo.lathe([Vector2(0.13, 0.02), Vector2(0.135, 0.09), Vector2(0.128, 0.09), Vector2(0.123, 0.02)], 24, "crownband"), mt)
			for i in 8:
				var a := TAU * i / 8.0
				var pt := P(root, Geo.prism(0.07, 0.09 if i % 2 == 0 else 0.06, 0.012), mt, Vector3(cos(a) * 0.13, 0.13 if i % 2 == 0 else 0.115, sin(a) * 0.13))
				pt.rotation.y = -a + PI * 0.5
				if i % 2 == 0:
					P(root, Geo.sph(0.012, 6), mt, Vector3(cos(a) * 0.13, 0.18, sin(a) * 0.13))
			var gm: Material = _gem(p) if p["gem"] != null else Mats.mat(Color(0.8, 0.1, 0.1), 0.1, 0.0, Color(0.8, 0.1, 0.1), 1.5)
			for i in 4:
				var a := TAU * i / 4.0 + PI * 0.25
				P(root, Geo.sph(0.016, 8), gm, Vector3(cos(a) * 0.135, 0.055, sin(a) * 0.135))
			P(root, Geo.sph(0.022, 8), gm, Vector3(0, 0.06, -0.137))
	if p["gem"] != null and kind != "crown":
		P(root, Geo.sph(0.018, 8), _gem(p), Vector3(0, 0.1, -0.135))
	return root

## Armor pieces attached to the given rig joints (or to a free-standing dummy).
static func armor_parts(J: Dictionary, kind: String, p: Dictionary, w: float, h: float) -> Array:
	var made: Array = []
	var torso: Node3D = J["torso"]
	var mm := _metal(p)
	var mt := _trim(p)
	var ml := Mats.mat(p["leather"], 0.8, 0.0, Color.BLACK, 0.0, 0.2)
	var chest_m: Material
	match kind:
		"quilted": chest_m = Mats.mat(Color(0.62, 0.55, 0.42), 0.95, 0.0, Color.BLACK, 0.0, 0.2)
		"leather": chest_m = ml
		"chain": chest_m = Mats.mat((p["metal"] as Color).darkened(0.15), 0.55, 0.8, Color.BLACK, 0.0, 0.2)
		_: chest_m = mm
	made.append(P(torso, torso_mesh(), chest_m, Vector3(0, 0.0, -0.004), Vector3.ZERO, Vector3(w * 1.07, h * 1.01, w * 0.8)))
	match kind:
		"quilted":
			for i in 4:
				made.append(P(torso, Geo.torus(0.155 * w, 0.17 * w, 20, 4), chest_m, Vector3(0, (0.12 + i * 0.08) * h, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8)))
		"leather":
			for i in 10:
				var a := -0.9 + i * 0.2
				made.append(P(torso, Geo.sph(0.012 * w, 6), mt, Vector3(sin(a) * 0.2 * w, 0.36 * h + (i % 2) * 0.06 * h, -cos(a) * 0.135 * w)))
			made.append(P(torso, Geo.box(0.05 * w, 0.5 * h, 0.3 * w), ml, Vector3(0.08 * w, 0.32 * h, 0), Vector3(0, 0, 18)))
		"chain":
			made.append(P(J["hips"], Geo.cyl(0.18 * w, 0.24 * w, 0.28 * h, 14), chest_m, Vector3(0, -0.14 * h, 0)))
			made.append(P(torso, Geo.torus(0.15 * w, 0.18 * w, 18, 6), ml, Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.0, 1.6, 0.85)))
		"plate", "ornate":
			made.append(P(torso, Geo.torus(0.07 * w, 0.1 * w, 16, 5), mm, Vector3(0, 0.53 * h, 0)))
			made.append(P(torso, Geo.box(0.04 * w, 0.3 * h, 0.02), mt, Vector3(0, 0.32 * h, -0.135 * w)))
			for i in 3:
				made.append(P(J["hips"], Geo.cyl(0.17 * w + i * 0.012, 0.19 * w + i * 0.014, 0.08 * h, 14), mm, Vector3(0, -0.04 * h - i * 0.07 * h, 0)))
			if kind == "ornate":
				for i in 3:
					made.append(P(torso, Geo.torus(0.158 * w, 0.168 * w, 22, 4), mt, Vector3(0, (0.15 + i * 0.1) * h, 0), Vector3.ZERO, Vector3(1.0, 1.0, 0.8)))
				var gc: Color = p["gem"] if p["gem"] != null else Color(0.3, 0.6, 1.0)
				made.append(P(torso, Geo.sph(0.03 * w, 10), Mats.mat(gc, 0.1, 0.2, gc, 3.0), Vector3(0, 0.36 * h, -0.14 * w)))
	# pauldrons
	for side in [1, -1]:
		var key := "sh_r" if side == 1 else "sh_l"
		if not J.has(key):
			continue
		var shn: Node3D = J[key]
		match kind:
			"leather", "quilted":
				made.append(P(shn, Geo.sph(0.075 * w, 12, 0.5), ml if kind == "leather" else chest_m, Vector3(side * 0.01, 0.01, 0), Vector3(0, 0, -side * 15)))
			"chain":
				made.append(P(shn, Geo.sph(0.085 * w, 12, 0.5), chest_m, Vector3(side * 0.01, 0.0, 0), Vector3(0, 0, -side * 15)))
			_:
				made.append(P(shn, Geo.sph(0.11 * w, 16, 0.5), mm, Vector3(side * 0.02, 0.0, 0), Vector3(0, 0, -side * 22), Vector3(1.0, 0.9, 1.1)))
				made.append(P(shn, Geo.sph(0.1 * w, 16, 0.5), mt, Vector3(side * 0.04, -0.05 * h, 0), Vector3(0, 0, -side * 35), Vector3(1.0, 0.7, 1.05)))
				if kind == "ornate":
					var spk := P(shn, Geo.cone(0.025 * w, 0.12 * h, 8), mt, Vector3(side * 0.05 * w, 0.07 * h, 0))
					spk.rotation_degrees.z = -side * 30
					made.append(spk)
	if p["gem"] != null and kind != "ornate":
		made.append(P(torso, Geo.sph(0.022 * w, 8), _gem(p), Vector3(0, 0.4 * h, -0.14 * w)))
	return made

static func armor_item(kind: String, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var dummy := N(root, "torso", Vector3(0, -0.3, 0))
	var J := {"torso": dummy, "hips": N(root, "hips", Vector3(0, -0.38, 0)),
		"sh_r": N(dummy, "sh_r", Vector3(0.215, 0.48, 0)), "sh_l": N(dummy, "sh_l", Vector3(-0.215, 0.48, 0))}
	armor_parts(J, kind, p, 1.0, 1.0)
	return root

static func gloves(kind: String, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var m: Material = Mats.mat(p["leather"], 0.8) if kind == "gloves" else _metal(p)
	var mt := _trim(p)
	for side in [1, -1]:
		var g := N(root, "g", Vector3(side * 0.09, 0, 0), Vector3(0, side * 12, 0))
		P(g, Geo.box(0.085, 0.03, 0.1), m, Vector3(0, 0, 0))
		for f in 4:
			P(g, Geo.cap(0.011, 0.08, 6), m, Vector3(-0.03 + f * 0.02, 0, -0.085), Vector3(-90, 0, 0))
		P(g, Geo.cap(0.012, 0.06, 6), m, Vector3(side * -0.05, 0, -0.03), Vector3(-90, side * 40, 0))
		P(g, Geo.cyl(0.05, 0.045, 0.08, 12), m, Vector3(0, 0, 0.08), Vector3(90, 0, 0))
		P(g, Geo.torus(0.045, 0.056, 14, 4), mt, Vector3(0, 0, 0.115), Vector3(90, 0, 0))
		if kind == "gauntlets":
			for k in 3:
				P(g, Geo.box(0.09, 0.012, 0.025), mt, Vector3(0, 0.02, -0.02 + k * 0.03))
	if p["gem"] != null:
		P(root, Geo.sph(0.012, 6), _gem(p), Vector3(0.09, 0.02, 0.0))
	return root

static func boots(kind: String, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var m: Material = Mats.mat(p["leather"], 0.8) if kind == "boots" else _metal(p)
	var mt := _trim(p)
	for side in [1, -1]:
		var b := N(root, "b", Vector3(side * 0.1, 0, 0))
		P(b, Geo.cyl(0.055, 0.06, 0.22, 12), m, Vector3(0, 0.11, 0))
		P(b, Geo.box(0.1, 0.07, 0.22), m, Vector3(0, 0.0, -0.06))
		P(b, Geo.torus(0.052, 0.066, 14, 4), mt, Vector3(0, 0.22, 0))
		if kind == "greaves":
			P(b, Geo.sph(0.04, 8, 0.5), mt, Vector3(0, 0.03, -0.17), Vector3(-90, 0, 0))
			P(b, Geo.box(0.04, 0.18, 0.02), mt, Vector3(0, 0.12, -0.06))
	return root

static func belt(kind: String, p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var m := Mats.mat(p["leather"], 0.8)
	P(root, Geo.torus(0.14, 0.17, 24, 4), m, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.6, 0.8))
	P(root, Geo.box(0.06, 0.06, 0.02), _trim(p), Vector3(0, 0, -0.14))
	var pouches := 2 if kind == "sash" else 4
	for i in pouches:
		var a := 0.8 + i * 0.5
		P(root, Geo.box(0.05, 0.06, 0.035), Mats.mat((p["leather"] as Color).darkened(0.2), 0.85), Vector3(sin(a) * 0.15, -0.03, cos(a) * 0.12), Vector3(0, rad_to_deg(a), 0))
	if kind == "warbelt":
		for i in 6:
			var a := TAU * i / 6.0
			P(root, Geo.box(0.05, 0.05, 0.012), _metal(p), Vector3(sin(a) * 0.155, 0, cos(a) * 0.125), Vector3(0, rad_to_deg(a), 0))
	return root

static func ring(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mt := Mats.mat(p["trim"] if p["glow"] != null or (p["trim"] as Color).r > 0.6 else Color(0.85, 0.68, 0.3), 0.2, 1.0)
	P(root, Geo.torus(0.028, 0.036, 24, 8), mt, Vector3.ZERO, Vector3(90, 0, 0))
	P(root, Geo.cyl(0.012, 0.008, 0.012, 8), mt, Vector3(0, 0.038, 0))
	var gc: Color = p["gem"] if p["gem"] != null else Color(0.85, 0.85, 0.9)
	P(root, Geo.sph(0.013, 10), Mats.mat(gc, 0.05, 0.1, gc, 1.8), Vector3(0, 0.048, 0))
	return root

static func amulet(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mt := Mats.mat(Color(0.85, 0.68, 0.3) if p["glow"] == null else p["trim"], 0.2, 1.0)
	P(root, Geo.torus(0.085, 0.091, 32, 4), mt, Vector3(0, 0.0, 0), Vector3(90, 0, 0))
	var pend := P(root, Geo.extrude(PackedVector2Array([Vector2(0, 0.03), Vector2(0.025, 0.0), Vector2(0, -0.05), Vector2(-0.025, 0)]), 0.012, "pendant"), mt, Vector3(0, -0.12, 0))
	pend.scale = Vector3(1.3, 1.3, 1)
	var gc: Color = p["gem"] if p["gem"] != null else Color(0.3, 0.8, 0.5)
	P(root, Geo.sph(0.015, 10), Mats.mat(gc, 0.05, 0.1, gc, 2.0), Vector3(0, -0.12, -0.008))
	return root

static func potion(col: Color, id: String) -> Node3D:
	var root := Node3D.new()
	var prof: Array
	if id == "rejuv":
		prof = [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.065, 0.04), Vector2(0.05, 0.1), Vector2(0.022, 0.12), Vector2(0.022, 0.16), Vector2(0.0, 0.16)]
	elif id == "mp_potion":
		prof = [Vector2(0.0, 0.0), Vector2(0.04, 0.0), Vector2(0.045, 0.08), Vector2(0.03, 0.11), Vector2(0.018, 0.12), Vector2(0.018, 0.16), Vector2(0.0, 0.16)]
	else:
		prof = [Vector2(0.0, 0.0), Vector2(0.035, 0.0), Vector2(0.06, 0.04), Vector2(0.06, 0.07), Vector2(0.03, 0.105), Vector2(0.018, 0.12), Vector2(0.018, 0.16), Vector2(0.0, 0.16)]
	P(root, Geo.lathe(prof, 18, "bottle" + id), glass_mat())
	var inner := []
	for v in prof:
		if v.y < 0.1:
			inner.append(Vector2(max(v.x - 0.005, 0.0), v.y + 0.004))
	inner.append(Vector2(0.0, inner[inner.size() - 1].y))
	P(root, Geo.lathe(inner, 16, "liquid" + id), Mats.mat(col, 0.15, 0.0, col, 1.2))
	P(root, Geo.cyl(0.016, 0.014, 0.03, 8), Mats.mat(Color(0.45, 0.3, 0.18), 0.9), Vector3(0, 0.168, 0))
	return root

static func gold_pile(count: int) -> Node3D:
	var root := Node3D.new()
	var gm := Mats.mat(Color(1.0, 0.78, 0.3), 0.25, 1.0, Color(0.4, 0.25, 0.0), 0.2)
	var n: int = clampi(3 + count / 40, 3, 14)
	var rng := RandomNumberGenerator.new()
	rng.seed = count
	for i in n:
		var c := P(root, Geo.cyl(0.025, 0.025, 0.006, 12), gm, Vector3(rng.randf_range(-0.07, 0.07), 0.004 + (i % 4) * 0.006, rng.randf_range(-0.07, 0.07)))
		c.rotation_degrees = Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15))
	return root

## How an item model should lie on the ground (rotation applied to the model root).
static func ground_pose(slot: String) -> Vector3:
	match slot:
		"weapon": return Vector3(0, 0, 90)
		"shield": return Vector3(-90, 0, 0)
		"armor": return Vector3(-90, 0, 0)
		"helm": return Vector3(-20, 0, 15)
		"ring", "amulet": return Vector3(90, 0, 0)
	return Vector3.ZERO

## Lift so the model rests on the ground.
static func ground_lift(slot: String) -> float:
	match slot:
		"weapon": return 0.03
		"shield": return 0.05
		"armor": return 0.13
		"helm": return 0.1
		"gloves": return 0.02
		"boots": return 0.04
		"belt": return 0.04
		"ring", "amulet": return 0.01
	return 0.0
