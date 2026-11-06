class_name DougFx
extends RefCounted
## What Doug's skills look like (DougSkills does the gameplay): every event is drawn here on the caster and on his
## puppet for partners and PvP opponents (SkillFx.play -> DougFx.play). Draws only: no damage, no cooldowns.
## Lingering things (the peels on the ground, the double, the bounce's arc, the car) live in Hero.fxs and are moved
## every frame by update(), on the caster and on the puppet alike. Props are Meshy (Doug.prop).

const CONFETTI := [Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.2), Color(0.35, 0.75, 1.0), Color(0.5, 1.0, 0.45)]
const CREAM := Color(1.0, 0.97, 0.88)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var s := str(ev.get("s", ""))
	var e := str(ev.get("e", ""))
	match s + ":" + e:
		"u_cannon:boom":
			var bp: Vector3 = ev["p"]
			var br: float = float(ev.get("r", 4.5))
			_confetti(root, bp + Vector3(0, 0.8, 0), 2.0)
			Fx.ring(root, bp, br, Color(1.0, 0.85, 0.3), 0.5)
			Fx.burst(root, bp + Vector3(0, 0.4, 0), Color(0.6, 0.5, 0.4), 30, 5.0, 0.14, 0.6, false, -8.0)
			Fx.flash(root, bp + Vector3(0, 1.0, 0), Color(1.0, 0.8, 0.4), 4.0, 0.3, 8.0)
			SkillFx.snd(h, "boom", -2.0, 1.1)
		"pie:throw":
			var big := float(ev.get("r", 0.6))
			_fly(root, "pie", ev["p"], ev["q"], float(ev.get("x", 0.45)), 2.2 + big, big)
			SkillFx.snd(h, "swing_light", -4.0, 1.3)
		"pie:splat":
			var p: Vector3 = ev["p"]
			Fx.burst(root, p + Vector3(0, 0.9, 0), CREAM, 36, 4.0, 0.14, 0.6, false, -9.0)
			Fx.burst(root, p + Vector3(0, 0.9, 0), Color(0.72, 0.5, 0.26), 12, 3.0, 0.08, 0.5, false, -12.0)   # crust
			_splat_disc(root, p, 1.0)
			SkillFx.snd(h, "doug_splat", -1.0, randf_range(0.95, 1.05))
			for t in ev.get("t", []):
				if is_instance_valid(t):
					Fx.number(root, t.global_position + Vector3(0, 2.4, 0), "Pied!", CREAM)
		"peels:land":
			var list: Array = h.fxs.get("peels", [])
			var from_v: Variant = ev.get("q", null)     # Banana Bonanza: each peel is flung out of his hands first
			for p in ev.get("ps", PackedVector3Array()):
				var m := Doug.prop("banana")
				if m == null:
					m = MeshInstance3D.new()
					(m as MeshInstance3D).mesh = Geo.sph(0.18, 8)
				root.add_child(m)
				m.global_position = p + Vector3(0, 0.02, 0)
				m.rotation.y = randf() * TAU
				m.set_meta("t", float(ev.get("x", 8.0)))
				list.append(m)
				if from_v is Vector3:
					m.scale = Vector3.ONE * 0.01
					_fly(root, "banana", from_v, p + Vector3(0, 0.1, 0), 0.35, 1.6, 0.7)
					var tw := m.create_tween()
					tw.tween_interval(0.33)
					tw.tween_property(m, "scale", Vector3.ONE * 0.7, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
					tw.tween_callback(func(): Fx.burst(root, p + Vector3(0, 0.15, 0), Color(1.0, 0.9, 0.35), 8, 2.0, 0.06, 0.35, false, -9.0))
				else:
					m.scale = Vector3.ONE * 0.5
			h.fxs["peels"] = list
			SkillFx.snd(h, "swing_light", -6.0, 1.6)
		"peels:slip", "peels:gone":
			var p2: Vector3 = ev["p"]
			var list2: Array = h.fxs.get("peels", [])
			for i in range(list2.size() - 1, -1, -1):
				var n: Node3D = list2[i]
				if not is_instance_valid(n) or n.global_position.distance_to(p2) < 0.3:
					if is_instance_valid(n):
						n.queue_free()
					list2.remove_at(i)
			if e == "slip":
				Fx.burst(root, p2 + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.25), 20, 3.0, 0.1, 0.5, true, -8.0)
				Fx.number(root, p2 + Vector3(0, 2.0, 0), "Slipped!", Color(1.0, 0.9, 0.3))
				SkillFx.snd(h, "doug_slip", -1.0)
		"slide:honk":
			SkillFx.snd(h, "doug_honk", -2.0)
			h.fxs["slide_t"] = 0.6
		"doppel:start":
			_confetti(root, ev["p"] + Vector3(0, 1.0, 0), 1.0)
			SkillFx.snd(h, "portal", -6.0, 1.6)
			h.fxs["hide_t"] = float(ev.get("x", 1.8))
			var d := _double(h)
			if d != null:
				root.add_child(d)
				d.global_position = ev["p"]
				var dir: Vector3 = ev.get("d", h.facing())
				d.rotation.y = atan2(-dir.x, -dir.z)
				d.set_meta("d", dir)
				d.set_meta("t", float(ev.get("r", 3.0)))
				h.fxs["double"] = d
		"doppel:pop":
			var dn = h.fxs.get("double")
			if dn != null and is_instance_valid(dn):
				dn.queue_free()
			h.fxs.erase("double")
			_confetti(root, ev["p"] + Vector3(0, 1.0, 0), 1.3)
			Fx.ring(root, ev["p"], 3.0, Color(1.0, 0.85, 0.3), 0.4)
			SkillFx.snd(h, "doug_pop", 0.0)
		"juggle:pin":
			var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
			for i in ps.size() - 1:
				_fly(root, "pin", ps[i], ps[i + 1], 0.16, 0.6, 0.35, 0.16 * i, true)
				Fx.burst(root, ps[i + 1], Color(1.0, 0.55, 0.15), 10, 2.0, 0.08, 0.35, true, 0.0)
			SkillFx.snd(h, "fireball", -8.0, 1.5)
		"bounce:mark":
			var q: Vector3 = ev["q"]
			Fx.telegraph(root, q, 1.6, float(ev.get("x", 1.3)) * 0.78, Color(1.0, 0.85, 0.3))
			var tr := Doug.prop("trampoline")
			if tr != null:
				tr.scale = Vector3.ONE * 0.9
				root.add_child(tr)
				tr.global_position = ev["p"]
				var tw := tr.create_tween()
				tw.tween_interval(1.0)
				tw.tween_property(tr, "scale", Vector3.ONE * 0.01, 0.25)
				tw.tween_callback(tr.queue_free)
			h.fxs["bounce"] = {"t": 0.0, "dur": float(ev.get("x", 1.3))}
			SkillFx.snd(h, "doug_boing", -1.0)          # the trampoline, and the whistle up
			SkillFx.snd(h, "doug_whistle", -5.0)
		"bounce:flop":
			var p3: Vector3 = ev["p"]
			Fx.ring(root, p3, 3.0, Color(1.0, 0.85, 0.3), 0.45)
			Fx.burst(root, p3 + Vector3(0, 0.3, 0), Color(0.6, 0.52, 0.4, 0.7), 40, 5.0, 0.2, 0.7, false, -6.0, 70.0)
			_confetti(root, p3 + Vector3(0, 0.6, 0), 0.7)
			SkillFx.shake(h, 0.35)
			h.fxs.erase("bounce")
		"car:start":
			var car := Doug.prop("car")
			if car != null:
				car.name = "clown_car"
				car.scale = Vector3.ONE * 0.9
				h.add_child(car)
				car.position = Vector3(0, 0, 0)
				car.rotation.y = -PI * 0.5      # the model's bonnet is along -x: turn it to his facing (-z)
				h.fxs["car"] = car
				h.fxs["car_t"] = float(ev.get("x", 5.0))
			SkillFx.snd(h, "doug_klaxon", 0.0)
			_confetti(root, ev["p"] + Vector3(0, 0.8, 0), 0.8)
		"car:ram":
			Fx.burst(root, ev["p"] + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.3), 16, 4.0, 0.1, 0.4, true, -4.0)
			SkillFx.snd(h, "slam", -6.0, 1.4)
			SkillFx.shake(h, 0.15)
		"car:burst":
			_end_car(h)
			var p4: Vector3 = ev["p"]
			_confetti(root, p4 + Vector3(0, 1.0, 0), 2.0)
			SkillFx.snd(h, "doug_pop", 2.0, 0.8)
			for t in ev.get("t", []):
				if is_instance_valid(t):
					_mini(root, p4, t.global_position)
		_:
			return false
	return true

## A prop flying from a to b along an arc (`lift` metres up at the middle), spinning, then gone; `delay` first.
static func _fly(root: Node3D, prop: String, a: Vector3, b: Vector3, dur: float, lift: float, sc: float, delay := 0.0, burning := false) -> void:
	var m := Doug.prop(prop)
	if m == null:
		m = MeshInstance3D.new()
		(m as MeshInstance3D).mesh = Geo.sph(0.12, 8)
	var holder := Node3D.new()
	holder.add_child(m)
	m.scale = Vector3.ONE * sc
	root.add_child(holder)
	holder.global_position = a
	holder.visible = delay <= 0.0
	if burning:
		Fx.aura(holder, Color(1.0, 0.5, 0.15), 14, 0.6, 0.08, 0.4, 0.3, 0.1)
	var tw := holder.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): holder.visible = true)
	tw.tween_method(func(k: float):
		if not is_instance_valid(holder):
			return
		holder.global_position = a.lerp(b, k) + Vector3(0, sin(k * PI) * lift, 0)
		m.rotation = Vector3(k * TAU * 2.0, k * TAU, 0.0), 0.0, 1.0, dur)
	tw.tween_callback(holder.queue_free)

## A cream splat on the floor that fades.
## The cream left where a pie lands: a decal on the ground (so it lies on slopes and steps), a splash of cream with
## a ragged edge and flung droplets, fading after a few seconds. (Decals don't draw in the browser build's renderer:
## there the burst alone shows it.)
static func _splat_disc(root: Node3D, p: Vector3, r: float) -> void:
	var dc := Decal.new()
	dc.size = Vector3(r * 2.4, 1.2, r * 2.4)
	dc.texture_albedo = _splat_tex()
	dc.modulate = CREAM
	dc.albedo_mix = 1.0
	dc.upper_fade = 0.2
	dc.lower_fade = 0.4
	root.add_child(dc)
	dc.global_position = p + Vector3(0, 0.3, 0)
	dc.rotation.y = randf() * TAU
	var tw := dc.create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(dc, "modulate:a", 0.0, 1.2)
	tw.tween_callback(dc.queue_free)

static var _splat: ImageTexture

static func _splat_tex() -> ImageTexture:
	if _splat != null:
		return _splat
	const N := 128
	var img := Image.create(N, N, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4071
	var ph := [rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU]
	var drops := []
	for k in 11:
		var a := rng.randf() * TAU
		drops.append([Vector2(cos(a), sin(a)) * rng.randf_range(0.66, 0.95), rng.randf_range(0.025, 0.07)])
	for y in N:
		for x in N:
			var d := Vector2(x + 0.5 - N * 0.5, y + 0.5 - N * 0.5) / (N * 0.5)
			var th := d.angle()
			# a lumpy rim: the splash's lobes
			var rim: float = 0.5 + 0.1 * sin(5.0 * th + ph[0]) + 0.06 * sin(9.0 * th + ph[1]) + 0.04 * sin(14.0 * th + ph[2])
			var a := clampf((rim - d.length()) / 0.04, 0.0, 1.0)
			for dr in drops:
				a = maxf(a, clampf((dr[1] - d.distance_to(dr[0])) / 0.015, 0.0, 1.0))
			# whipped cream: brighter swirls in the middle, a faint shadow at the edge
			var shade := 0.86 + 0.14 * clampf(1.0 - d.length() / rim, 0.0, 1.0) + 0.05 * sin(d.length() * 40.0 + th * 3.0)
			img.set_pixel(x, y, Color(shade, shade * 0.98, shade * 0.92, a))
	img.generate_mipmaps()
	_splat = ImageTexture.create_from_image(img)
	return _splat

static func _confetti(root: Node3D, p: Vector3, k: float) -> void:
	for c in CONFETTI:
		Fx.burst(root, p, c, int(14 * k), 4.5 * k, 0.07, 1.1, false, -3.0, 180.0)

static var _balloon_sh: Shader     # one for every cast (a new Shader per cast compiled again each time)

## His balloon double: his own model, shiny (a balloon sheen over his colours), running.
static func _double(h: Hero) -> Node3D:
	if not Doug.model_ok():
		return null
	var d: Node3D = ResCache.inst(Doug.GLB)
	var root := Node3D.new()
	root.add_child(d)
	if _balloon_sh == null:
		_balloon_sh = Shader.new()
		_balloon_sh.code = """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
void fragment() {
	vec3 base = texture(tex, UV).rgb;
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = base * 1.1;
	ROUGHNESS = 0.08;
	SPECULAR = 1.0;
	EMISSION = vec3(1.0, 0.95, 0.85) * fr * 0.6;
}"""
	for mi in d.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var src := mesh.surface_get_material(si) as BaseMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = _balloon_sh
			if src != null and src.albedo_texture != null:
				sm.set_shader_parameter("tex", src.albedo_texture)
			(mi as MeshInstance3D).set_surface_override_material(si, sm)
	var ap := d.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null and ap.has_animation("run"):
		ap.play("run")
	return root

## A mini clown: a small Doug running from the car to his foe, then a pie in its face.
static func _mini(root: Node3D, from: Vector3, to: Vector3) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.global_position = from + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	if Doug.model_ok():
		var d: Node3D = ResCache.inst(Doug.GLB)
		d.scale = Vector3.ONE * 0.45
		holder.add_child(d)
		var ap := d.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null and ap.has_animation("run_fast"):
			ap.play("run_fast")
	var dir := to - holder.global_position
	dir.y = 0
	holder.rotation.y = atan2(-dir.x, -dir.z)
	var tw := holder.create_tween()
	tw.tween_property(holder, "global_position", Vector3(to.x, holder.global_position.y, to.z) - dir.normalized() * 0.6, 0.8)
	tw.tween_callback(func():
		Fx.burst(root, to + Vector3(0, 1.0, 0), CREAM, 24, 3.0, 0.12, 0.5, false, -9.0)
		_confetti(root, holder.global_position + Vector3(0, 0.5, 0), 0.4))
	tw.tween_callback(holder.queue_free)

static func _end_car(h: Hero) -> void:
	var car = h.fxs.get("car")
	if car != null and is_instance_valid(car):
		car.queue_free()
	h.fxs.erase("car")
	h.fxs.erase("car_t")

## Every frame (caster and puppet): the peels' timers, the double running, the bounce's arc, the hiding fade, the car.
static func update(h: Hero, delta: float) -> void:
	if h.fxs.is_empty():
		return
	if h.fxs.has("peels"):
		var list: Array = h.fxs["peels"]
		for i in range(list.size() - 1, -1, -1):
			var n = list[i]
			if not is_instance_valid(n):
				list.remove_at(i)
				continue
			n.set_meta("t", float(n.get_meta("t")) - delta)
			if float(n.get_meta("t")) <= 0.0:
				n.queue_free()
				list.remove_at(i)
	if h.fxs.has("double"):
		var d = h.fxs["double"]
		if d == null or not is_instance_valid(d):
			h.fxs.erase("double")
		else:
			d.global_position = h.game.world.move(d.global_position, (d.get_meta("d") as Vector3) * 4.2 * delta, 0.4)
			d.set_meta("t", float(d.get_meta("t")) - delta)
			if float(d.get_meta("t")) < -0.5:
				d.queue_free()          # (a partner's copy ends itself if the pop is lost)
				h.fxs.erase("double")
	if h.fxs.has("hide_t"):
		var t := float(h.fxs["hide_t"]) - delta
		h.fxs["hide_t"] = t
		# unseen: his partners see nothing of him, he sees himself as a ghost
		var a := 0.0 if h.puppet else 0.35
		if t <= 0.0:
			a = 1.0
			h.fxs.erase("hide_t")
		_alpha(h, a)
	if h.fxs.has("bounce"):
		var b: Dictionary = h.fxs["bounce"]
		b["t"] = float(b["t"]) + delta
		var k := clampf((float(b["t"]) / maxf(float(b["dur"]), 0.01) - 0.15) / 0.63, 0.0, 1.0)
		h.rig.position.y = sin(k * PI) * 4.0
		if k >= 1.0:
			h.rig.position.y = 0.0
	elif h.rig.position.y > 0.01 and not h.has_meta("rolled"):
		h.rig.position.y = 0.0
	if h.fxs.has("car_t"):
		h.fxs["car_t"] = float(h.fxs["car_t"]) - delta
		if float(h.fxs["car_t"]) < -1.0:
			_end_car(h)

static func _alpha(h: Hero, a: float) -> void:
	h.rig.visible = a > 0.01
	for mi in h.rig.find_children("*", "MeshInstance3D", true, false):
		(mi as GeometryInstance3D).transparency = 1.0 - a

static func clear(h: Hero) -> void:
	for n in h.fxs.get("peels", []):
		if is_instance_valid(n):
			n.queue_free()
	var d = h.fxs.get("double")
	if d != null and is_instance_valid(d):
		d.queue_free()
	_end_car(h)
	if h.fxs.has("hide_t"):
		_alpha(h, 1.0)
