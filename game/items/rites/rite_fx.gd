class_name RiteFx
extends RefCounted
## How a rite's or gem's proc looks on every player's game: the "run" fx events (Hero.fx -> SkillFx ->
## RunTalents.play_fx) that ProcHits and RiteProcs send, a gem found ("gem", the run window), and the ones a few skills
## borrow (Blast Arrow's "flare", the dragons' "freeze"). It only draws.

const FLARE := [Color(1.0, 0.5, 0.15), Color(0.6, 1.0, 0.3)]

static func play(h: Hero, ev: Dictionary) -> void:
	var root: Node3D = h.game.world.fx_root
	var p: Vector3 = ev.get("p", h.global_position)
	var r: float = float(ev.get("r", 3.0))
	match str(ev.get("e", "")):
		"flare":
			var col: Color = FLARE[clampi(int(ev.get("n", 0)), 0, 1)]
			Fx.burst(root, p + Vector3(0, 0.8, 0), col, 28, r * 1.6, 0.18, 0.55, true, 1.5)
			Fx.ring(root, p, r, col, 0.45)
			Fx.flash(root, p + Vector3(0, 1.0, 0), col, 3.0, 0.3, r * 2.0)
			Sfx.play_at("thunder_blast", p, -9.0, 1.5)
		"shards":
			Fx.burst(root, p + Vector3(0, 1.0, 0), Color(0.75, 0.92, 1.0), 26, r * 1.8, 0.12, 0.6, true, -8.0)
			Fx.ring(root, p, r, Color(0.6, 0.88, 1.0), 0.4)
			Sfx.play_at("ice_burst", p, -6.0, randf_range(0.9, 1.15))
		"cloud":
			PlagueSmoke.puffs(root, p + Vector3(0, 0.4, 0), PlagueSmoke.FOG, Color(0.45, 0.9, 0.3, 0.8), 10, r * 0.9, 1.6, 1.2, r * 0.4, 0.4, 80.0, Vector3.UP, true)
			Fx.ring(root, p, r, Color(0.5, 1.0, 0.3), 0.6)
			Sfx.play_at("ice_shatter", p, -10.0, 0.6)
		"freeze":
			Fx.burst(root, p + Vector3(0, 1.0, 0), Color(0.82, 0.95, 1.0), 30, 1.5, 0.15, 1.0, true, -1.0)
			Fx.ring(root, p, r, Color(0.7, 0.92, 1.0), float(ev.get("x", 1.5)))
			Sfx.play_at("ice_shatter", p, -4.0, 0.8)
		"chain", "ricochet", "spread":
			var ps: PackedVector3Array = ev.get("ps", PackedVector3Array())
			var col := Color(0.75, 0.8, 1.0)
			if ev["e"] == "ricochet":
				col = Color(1.0, 0.92, 0.7)
			elif ev["e"] == "spread":
				col = Color(0.5, 1.0, 0.3)
			if ev["e"] == "chain":
				# the Arc skill's own lightning (the Blender bolts, the strike on each foe), leaping in turn
				ArcFx.chain(h, root, ps, Vector3.ZERO, ArcFx.STORM, 1.25)
				Sfx.play_at("arc_zap", ps[0], -5.0)
			else:
				for i in ps.size() - 1:
					Fx.bolt(root, ps[i], ps[i + 1], col, 0.18)
					Fx.burst(root, ps[i + 1], col, 8, 2.0, 0.08, 0.3, true, -3.0)
		"bolt":
			ArcFx.bolt(root, p + Vector3(randf_range(-1, 1), 14.0, randf_range(-1, 1)), p + Vector3(0, 0.2, 0), 0.3, 1.4, ArcFx.STORM, h.game)
			Fx.ring(root, p, r, Color(0.7, 0.75, 1.0), 0.35)
			Fx.flash(root, p + Vector3(0, 2.0, 0), Color(0.7, 0.75, 1.0), 4.0, 0.2, 8.0)
			Sfx.play_at("arc_hit", p, -4.0)
		"undying":
			var col2 := Color(1.0, 0.55, 0.15) if int(ev.get("n", 0)) == 1 else Color(1.0, 0.9, 0.55)
			Fx.burst(root, p + Vector3(0, 1.0, 0), col2, 40, 4.0, 0.2, 0.8, true, 2.0)
			Fx.ring(root, p, 5.0, col2, 0.7)
			Fx.pillar(root, p, col2, 1.0)
			Sfx.play("relic_ting", -2.0)
		"echo":
			Fx.ring(root, p, 1.4, Color(0.55, 0.85, 1.0), 0.35, 0.1)
		"gem":
			Fx.pillar(root, p, Color(0.9, 0.95, 1.0), 1.2)
