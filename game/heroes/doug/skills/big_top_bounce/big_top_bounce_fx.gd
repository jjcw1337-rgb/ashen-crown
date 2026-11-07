class_name BigTopBounceFx
extends RefCounted
## What a belly-flop leap looks like (Big Top Bounce and Human Cannonball, DougFx hands their "bounce" events here):
## "mark" slams down the Meshy trampoline (trampoline.glb) where he stands, marks where he'll land and whistles, and
## lifts his body along the arc (update); "flop" rings and dusts the ground where he lands. Draws only.

const TRAMPOLINE := "res://game/heroes/doug/skills/big_top_bounce/trampoline.glb"

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev.get("e", "")):
		"mark":
			var q: Vector3 = ev["q"]
			Fx.telegraph(root, q, 1.6, float(ev.get("x", 1.3)) * 0.78, Color(1.0, 0.85, 0.3))
			var tr := ResCache.inst(TRAMPOLINE) as Node3D
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
		"flop":
			var p3: Vector3 = ev["p"]
			Fx.ring(root, p3, 3.0, Color(1.0, 0.85, 0.3), 0.45)
			Fx.burst(root, p3 + Vector3(0, 0.3, 0), Color(0.6, 0.52, 0.4, 0.7), 40, 5.0, 0.2, 0.7, false, -6.0, 70.0)
			DougFx.confetti(root, p3 + Vector3(0, 0.6, 0), 0.7)
			SkillFx.shake(h, 0.35)
			h.fxs.erase("bounce")
		_:
			return false
	return true

## Every frame: his body up along the arc (BigTopBounce's timing), and down again after.
static func update(h: Hero, delta: float) -> void:
	if h.fxs.has("bounce"):
		var b: Dictionary = h.fxs["bounce"]
		b["t"] = float(b["t"]) + delta
		var k := clampf((float(b["t"]) / maxf(float(b["dur"]), 0.01) - BigTopBounce.ARC_FROM) / (BigTopBounce.ARC_TO - BigTopBounce.ARC_FROM), 0.0, 1.0)
		h.rig.position.y = sin(k * PI) * 4.0
		if k >= 1.0:
			h.rig.position.y = 0.0
	elif h.rig.position.y > 0.01 and not h.has_meta("rolled"):
		h.rig.position.y = 0.0
