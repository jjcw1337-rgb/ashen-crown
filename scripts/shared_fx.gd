class_name SharedFx
extends RefCounted
## What the shared skills (SharedSkills) look and sound like, for the caster and his puppet alike (SkillFx.play
## hands their events here, whatever the hero's class). Draws only.

const EARTH := Color(0.85, 0.6, 0.32)
const ICE := Color(0.6, 0.85, 1.0)
const STORM := Color(0.75, 0.7, 1.0)
const FLAME := Color(1.0, 0.5, 0.15)
const CRY := Color(1.0, 0.3, 0.2)

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	var e := str(ev["e"])
	match str(ev["s"]):
		"earthshatter":
			match e:
				"cast":
					SkillFx.snd(h, "swing_heavy", -6.0, 0.7)
				"windup":
					Fx.arc_telegraph(root, h.global_position, ev["d"], 5.0, 50.0, float(ev["x"]), EARTH)
				"impact":
					var d: Vector3 = ev["d"]
					var p: Vector3 = ev["p"]
					for i in 4:
						var at := p + d * (1.0 + i * 1.2)
						Fx.burst(root, at + Vector3(0, 0.1, 0), Color(0.45, 0.36, 0.26, 0.8), 14, 3.0 + i, 0.18, 0.7, false, -7.0, 50.0, Vector3.UP)
					Fx.ring(root, p + d * 2.2 + Vector3(0, 0.05, 0), 3.0, EARTH, 0.45)
					SkillFx.snd(h, "slam", -2.0, 0.8)
					SkillFx.snd(h, "boom", -9.0, 0.7)
					SkillFx.shake(h, 0.35)
				_:
					return false
		"frost_nova":
			match e:
				"cast":
					SkillFx.snd(h, "spirit_dart", -10.0, 0.7)
					Fx.burst(root, SkillFx.hand(h, true), ICE, 10, 1.2, 0.08, 0.4)
				"impact":
					var p: Vector3 = ev["p"] + Vector3(0, 0.05, 0)
					Fx.ring(root, p, float(ev["r"]), ICE, 0.5)
					Fx.ring(root, p, float(ev["r"]) * 0.6, ICE.lightened(0.3), 0.35)
					Fx.burst(root, p + Vector3(0, 0.4, 0), ICE, 40, 6.0, 0.1, 0.6, true, -2.0, 90.0, Vector3.UP)
					SkillFx.snd(h, "ice_shatter", -3.0, 1.0)
					SkillFx.shake(h, 0.12)
				_:
					return false
		"arc":
			match e:
				"cast":
					Fx.burst(root, SkillFx.hand(h, true), STORM, 8, 1.5, 0.06, 0.3)
				"impact":
					var ps: PackedVector3Array = ev["ps"]
					for i in ps.size() - 1:
						Fx.bolt(root, ps[i], ps[i + 1], STORM, 0.25)
						Fx.burst(root, ps[i + 1], STORM, 10, 3.0, 0.06, 0.3)
					if ps.size() < 2:
						Fx.bolt(root, ps[0], ps[0] + (ev["d"] as Vector3) * 6.0, STORM, 0.2)
					SkillFx.snd(h, "thunder_strike", -8.0, 1.35)
				_:
					return false
		"flame_wave":
			match e:
				"cast":
					SkillFx.snd(h, "fuse", -12.0, 1.0)
				"impact":
					var d: Vector3 = ev["d"]
					var p: Vector3 = ev["p"]
					var n := int(float(ev["r"]) / 1.1)
					SkillFx.snd(h, "fireball", -4.0, 0.9)
					# the wall: the game's simulated fire (FireFx) rising one after another along the line and sinking
					# back, a burst of flame at each; one light rides the middle of it (a light per fire would be many)
					var side := d.cross(Vector3.UP).normalized()
					for i in n:
						var at := p + d * (1.0 + i * 1.1) + side * (0.35 if i % 2 == 0 else -0.35)
						at.y = h.game.world.height_at(at.x, at.z)
						var tm := h.get_tree().create_timer(i * 0.05, false)
						tm.timeout.connect(func():
							if not is_instance_valid(root):
								return
							var f := FireFx.make(root, at, "campfire", 1.5, FLAME, i == n / 2, false, i % 2 == 0)
							f.scale = Vector3.ONE * 0.2
							var tw := f.create_tween()
							tw.tween_property(f, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
							tw.tween_interval(0.7)
							tw.tween_property(f, "scale", Vector3(1.0, 0.05, 1.0), 0.5).set_ease(Tween.EASE_IN)
							tw.tween_callback(f.queue_free)
							Fx.burst(root, at + Vector3(0, 0.3, 0), FLAME, 12, 3.0, 0.14, 0.45, true, 3.0, 35.0, Vector3.UP))
				_:
					return false
		"war_cry":
			match e:
				"cast":
					pass
				"impact":
					var p: Vector3 = ev["p"] + Vector3(0, 0.05, 0)
					Fx.ring(root, p, SharedSkills.CRY_R, CRY, 0.6)
					Fx.burst(root, p + Vector3(0, 1.4, 0), CRY, 24, 4.0, 0.1, 0.5, true, 0.0, 180.0, Vector3.UP)
					SkillFx.snd(h, "battle_cry", -2.0, 1.0)
					SkillFx.shake(h, 0.2)
				_:
					return false
		_:
			return false
	return true
