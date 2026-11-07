class_name HauntingGraspFx
extends RefCounted
## Haunting Grasp's look on every game (HauntingGrasp is its rules). Draws only: "impact" {p: the ground, x: the
## hold, r: its reach}: the hands burst out of the earth round it, close and sink again as the hold ends.

const SPIRIT := SpiritFx.SPIRIT
const VIOLET := SpiritFx.VIOLET
const NIGHT := SpiritFx.NIGHT

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"cast":
			pass
		"impact":
			var at: Vector3 = ev["p"]
			grasp(root, at, float(ev.get("r", Skill.num("grasp", "radius", 3.5))), float(ev.get("x", 2.5)))
			Sfx.play_at("slam", at, -4.0, 0.85)
			Sfx.play_at("shackles", at, -8.0, 1.15)
			SkillFx.shake(h, 0.3)
		_:
			return false
	return true

## Spectral hands bursting up out of the ground round a point: long-fingered claws of spirit-light reaching up and
## closing, on a dark stain that spreads under them; they sink again as the hold ends.
static func grasp(root: Node3D, pos: Vector3, radius: float, dur: float) -> Node3D:
	var n := Node3D.new()
	root.add_child(n)
	n.global_position = pos
	# the stain: a dark disc with a violet rim, grown out
	var stain := MeshInstance3D.new()
	stain.mesh = SpiritFx.disc_mesh()
	var sm := SpiritFx.floor_mat(VIOLET, 0.0)
	stain.material_override = sm
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(stain)
	stain.position.y = 0.04
	stain.scale = Vector3.ONE * 0.2
	var tw := stain.create_tween()
	tw.tween_property(stain, "scale", Vector3.ONE * radius, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(maxf(dur - 0.6, 0.1))
	tw.tween_method(func(v: float): sm.set_shader_parameter("amt", v), 1.0, 0.0, 0.5)
	sm.set_shader_parameter("amt", 1.0)
	# the hands: eight round the ring, two in the middle, each a palm and four fingers, rising then closing
	var hands := []
	for i in 9:
		var a := TAU * i / 8.0 + 0.3
		var r := radius * (0.72 if i < 8 else 0.0) + (randf_range(-0.2, 0.2) if i < 8 else 0.0)
		var h := Node3D.new()
		n.add_child(h)
		h.position = Vector3(cos(a) * r, -0.9, sin(a) * r)
		h.rotation.y = -a + PI * 0.5 + randf_range(-0.4, 0.4)
		var palm := MeshInstance3D.new()
		palm.mesh = Geo.cyl(0.07, 0.11, 0.9, 7)
		palm.material_override = Mats.glow_unique(VIOLET.lerp(NIGHT, 0.4), 1.1, 0.0, 0.9)
		palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		palm.position.y = 0.45
		h.add_child(palm)
		var fingers := []
		for k in 4:
			var f := MeshInstance3D.new()
			f.mesh = SpiritFx.claw_mesh()
			f.material_override = Mats.glow_unique(SPIRIT.lerp(VIOLET, 0.35), 1.5, 0.0, 0.0)
			f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			f.position = Vector3((k - 1.5) * 0.06, 0.92, 0.0)
			f.rotation_degrees = Vector3(180.0 - 35.0, 0.0, (k - 1.5) * 10.0)   # the claws point up, curling inward
			f.scale = Vector3(2.6, 0.42, 2.6)
			h.add_child(f)
			fingers.append(f)
		hands.append([h, fingers])
		var rise := h.create_tween()
		rise.tween_interval(0.03 * i)
		rise.tween_property(h, "position:y", 0.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		# the fingers close on whatever is there
		for f in fingers:
			var cl: Tween = f.create_tween()
			cl.tween_interval(0.25 + 0.03 * i)
			cl.tween_property(f, "rotation_degrees:x", 180.0 - 85.0, 0.18).set_ease(Tween.EASE_IN)
		var sink := h.create_tween()
		sink.tween_interval(maxf(dur - 0.45, 0.1))
		sink.tween_property(h, "position:y", -1.0, 0.45).set_ease(Tween.EASE_IN)
	n.set_meta("hands", hands)
	SpiritFx.burst(root, pos + Vector3(0, 0.2, 0), Color(0.08, 0.04, 0.12, 0.85), 30, 3.0, 0.35, 0.8, false, 1.5, 70.0)
	SpiritFx.burst(root, pos + Vector3(0, 0.3, 0), VIOLET, 30, 4.5, 0.1, 0.6, true, 1.0, 60.0)
	Fx.flash(root, pos + Vector3(0, 1.0, 0), VIOLET, 2.5, 0.5, radius * 2.5)
	SpiritFx.free_later(n, dur + 0.1)
	return n
