class_name Mossbeard
extends BossBrain
## Old Mossbeard (kind hermit), the Verdant Reach's mushroom boss (the Mycelial Grotto): keeps his distance and makes
## the ground itself dangerous. His mushrooms are PoisonMushroom; his look is MossbeardFx.
##   Spore Bolt     a poison bolt (his basic, the "poison" projectile).
##   Sprouting      his signature: 3 poison mushrooms burst up round the heroes (max MAX_SHROOMS of his own); each
##                  breathes a cloud of poison every 1.5 s: where you can stand changes, until you cut them down.
##   Thorn Snare    roots erupt under his target after a green ring (1.0 s): rooted and hurt.
##   Spore Step     under 60% life he vanishes in spores and steps out of one of his mushrooms.
##   Bramble Burst  under 30%: thorns lash out round him (4.5 m), throwing heroes back.

const MAX_SHROOMS := 6
const MOVES := {
	"bb_bolt": [1.0, 0.55, "cast"], "bb_sprout": [1.5, 0.6, "cast"], "bb_snare": [1.3, 0.75, "cast"],
	"bb_step": [0.9, 0.5, "cast"], "bb_burst": [1.4, 0.6, "slam"],
}

func moves() -> Dictionary:
	return MOVES

func keep_at() -> float:
	return 8.0

func back_off() -> float:
	return 5.0

func tracks(m: String) -> bool:
	return m == "bb_bolt"

func choose(_tgt: Hero, dist: float) -> String:
	var frac := e.life / maxf(e.max_life, 1.0)
	if frac < 0.3 and dist < 4.5 and ready("bb_burst"):
		return "bb_burst"
	if frac < 0.6 and ready("bb_step") and _shrooms().size() > 0 and dist < 6.0:
		return "bb_step"
	if ready("bb_sprout") and _shrooms().size() < MAX_SHROOMS:
		return "bb_sprout"
	if ready("bb_snare") and dist < 12.0:
		return "bb_snare"
	if ready("bb_bolt") and dist < 12.0:
		return "bb_bolt"
	return ""

func start(m: String, warn: float) -> void:
	match m:
		"bb_bolt":
			cds[m] = 1.8
		"bb_sprout":
			cds[m] = 12.0
			e._fx("bb_sprout_tele")
		"bb_snare":
			cds[m] = 7.0
			e._fx("bb_snare_tele:%.1f,%.1f,%.2f" % [aim.x, aim.z, warn])
		"bb_step":
			cds[m] = 10.0
		"bb_burst":
			cds[m] = 9.0
			e._fx("bb_burst_tele:%.2f" % warn)

func land(_tgt: Hero) -> void:
	var at := e.global_position
	match move:
		"bb_bolt":
			e._shoot(aim, "poison")
		"bb_sprout":
			var n := 0
			for h in heroes_in(at, 26.0):
				if n >= 3 or _shrooms().size() >= MAX_SHROOMS:
					break
				var a2 := randf() * TAU
				var p: Vector3 = e.game.world.free_spot_near(h.global_position + Vector3(cos(a2), 0, sin(a2)) * randf_range(2.5, 4.5), 1.0)
				_sprout(p)
				n += 1
			while n < 3 and _shrooms().size() < MAX_SHROOMS:
				var a3 := randf() * TAU
				_sprout(e.game.world.free_spot_near(at + Vector3(cos(a3), 0, sin(a3)) * randf_range(4.0, 9.0), 1.0))
				n += 1
		"bb_snare":
			e._fx("bb_snare:%.1f,%.1f" % [aim.x, aim.z])
			for h in heroes_in(aim, 2.0):
				h.take_hit(e.roll() * 0.9, aim, "root", "poison")
		"bb_step":
			var ss := _shrooms()
			if not ss.is_empty():
				var to: Vector3 = ss[randi() % ss.size()].global_position
				e._fx("bb_step:%.1f,%.1f" % [at.x, at.z])
				e.global_position = e.game.world.free_spot_near(to + Vector3(1.2, 0, 0), 1.0)
				e._fx("bb_step:%.1f,%.1f" % [e.global_position.x, e.global_position.z])
		"bb_burst":
			e._fx("bb_burst")
			for h in heroes_in(at, 4.5):
				h.take_hit(e.roll() * 1.3, at, "sweep", "poison")

## His own mushrooms (his camp's and the ones he sprouted: his pack), never another camp's.
func _shrooms() -> Array:
	return e.game.world.enemies_root.get_children().filter(func(x) -> bool: return x is Enemy and not x.dead and x.kind == "spore_shroom" and x.pack_id == e.pack_id)

func _sprout(p: Vector3) -> void:
	var s: Enemy = e.game.spawn_enemy("spore_shroom", p, e.level, false, "", e.pack_id)
	if s != null:
		s.aggro = true
		s._fx("bb_shroom_up")
