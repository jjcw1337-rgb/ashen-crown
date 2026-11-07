class_name DeathMarkFx
extends RefCounted
## Death Mark's look on every game (DeathMark is its rules), in the Wraith's own language (soul rings, spirit
## bursts, wisps). Draws only:
##  "mark" {p: the point, t: [the foe marked], x: seconds}: a violet aura and a pale ring over the foe, and a soul ring
##    pulsing under it, tightening, until the mark tears;
##  "pop" {p, x: what it tore out}: the soul torn out and drunk back.

const VIOLET := SpiritFx.VIOLET
const PALE := SpiritFx.PALE

static func play(h: Hero, ev: Dictionary) -> bool:
	var root: Node3D = h.game.world.fx_root
	match str(ev["e"]):
		"mark":
			var foes: Array = ev.get("t", [])
			if not foes.is_empty() and is_instance_valid(foes[0]):
				var e: Node3D = foes[0]
				var at: Vector3 = e.global_position
				var secs: float = float(ev.get("x", 3.0))
				# (a player is their hero on another game: a man's height)
				var tall: float = float(e.get("height")) if e is Enemy else 1.0
				SpiritFx.ring(root, at, 1.6, VIOLET, 0.6)
				SpiritFx.burst(root, at + Vector3(0, 1.0, 0), VIOLET, 22, 2.5, 0.1, 0.6, true, 0.5)
				var a := Fx.aura(e, VIOLET, 16, 0.25, 0.09, 0.9, 0.5, 0.45, 40.0, Vector3(0, 1.1, 0))
				a.name = "death_mark"
				SpiritFx.free_later(a, secs)
				var ring := Fx.aura(e, PALE, 8, 0.1, 0.07, 0.6, 0.0, 0.6, 10.0, Vector3(0, tall * 2.0 + 0.4, 0))
				SpiritFx.free_later(ring, secs)
				# a violet soul ring pulsing under the marked foe every 0.6 s until the mark tears (tightening as it nears)
				var tw := e.create_tween()
				for k in int(secs / 0.6):
					tw.tween_interval(0.6)
					var rr := 1.8 - 0.25 * k
					tw.tween_callback(func():
						if is_instance_valid(e) and not e.get("dead") and is_instance_valid(root):
							SpiritFx.ring(root, e.global_position, maxf(0.8, rr), VIOLET, 0.45, 0.35))
			SkillFx.snd(h, "shade_in", -2.0, 0.7)
		"pop":
			var p: Vector3 = ev["p"]
			SpiritFx.pulse(root, p + Vector3(0, 1.0, 0), VIOLET, 2.6, 0.45)
			SpiritFx.ring(root, p, 2.8, VIOLET, 0.5)
			SpiritFx.burst(root, p + Vector3(0, 1.0, 0), PALE, 40, 5.0, 0.12, 0.6, true, 0.0)
			SpiritFx.soul_wisp(root, p + Vector3(0, 1.2, 0), h, 0.5)
			Fx.flash(root, p + Vector3(0, 1.2, 0), VIOLET, 4.0, 0.35, 7.0)
			Sfx.play_at("death_mark_pop", p, 0.0)
			SkillFx.shake(h, 0.3)
		_:
			return false
	return true
