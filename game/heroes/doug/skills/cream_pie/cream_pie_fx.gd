class_name CreamPieFx
extends RefCounted
## What a cream pie looks like (Cream Pie and Pie Barrage, DougFx hands their events here): "throw" flies a pie (the
## Meshy pie, pie.glb) from his hands to where it lands; "splat" bursts it in cream and crust, leaves a splash of cream
## on the ground, and calls "Pied!" over the foe it hit. Draws only.

const PIE := "res://game/heroes/doug/skills/cream_pie/pie.glb"

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev.get("e", "")):
		"throw":
			var big := float(ev.get("r", 0.6))
			DougFx.fly(root, PIE, ev["p"], ev["q"], float(ev.get("x", 0.45)), 2.2 + big, big)
			SkillFx.snd(h, "swing_light", -4.0, 1.3)
		"splat":
			var p: Vector3 = ev["p"]
			Fx.burst(root, p + Vector3(0, 0.9, 0), DougFx.CREAM, 36, 4.0, 0.14, 0.6, false, -9.0)
			Fx.burst(root, p + Vector3(0, 0.9, 0), Color(0.72, 0.5, 0.26), 12, 3.0, 0.08, 0.5, false, -12.0)   # crust
			_splat_disc(root, p, 1.0)
			SkillFx.snd(h, "doug_splat", -1.0, randf_range(0.95, 1.05))
			for t in ev.get("t", []):
				if is_instance_valid(t):
					Fx.number(root, t.global_position + Vector3(0, 2.4, 0), "Pied!", DougFx.CREAM)
		_:
			return false
	return true

## The cream left where a pie lands: a decal on the ground (so it lies on slopes and steps), a splash of cream with
## a ragged edge and flung droplets, fading after a few seconds. (Decals don't draw in the browser build's renderer:
## there the burst alone shows it.)
static func _splat_disc(root: Node3D, p: Vector3, r: float) -> void:
	var dc := Decal.new()
	dc.size = Vector3(r * 2.4, 1.2, r * 2.4)
	dc.texture_albedo = _splat_tex()
	dc.modulate = DougFx.CREAM
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
