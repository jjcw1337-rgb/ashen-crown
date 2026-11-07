class_name Hrimgar
extends BossBrain
## Hrimgar the Frostbound (kind ice_troll), the Verdant Reach's frost boss (Frostfang Hollow): heavy and slow, every
## blow wound up where you can see it. His look is HrimgarFx.
##   Glacial Slam   both fists down: a ring 6 m round him (1.0 s warning), freezes those in it.
##   Frost Lances   a line of ice spears bursting out of the floor toward his target (crack line, 0.9 s), chills.
##   Rime Roar      a cone of frozen breath, 9 m (0.8 s), chills and pushes back.
##   Avalanche      under half life, every 16 s: ice falls on marked circles round the hall and under each hero.
##   (in reach)     a clubbing swing.

const MOVES := {
	# move: [seconds, impact at (0..1), style]
	"bb_slam": [1.9, 0.55, "slam"], "bb_lances": [1.6, 0.6, "smash"], "bb_roar": [1.5, 0.55, "cast"],
	"bb_avalanche": [2.4, 0.6, "cast"], "bb_swing": [1.25, 0.5, "over"],
}

var marks: Array = []          # avalanche circles (positions)

func moves() -> Dictionary:
	return MOVES

func tracks(m: String) -> bool:
	return m == "bb_swing"

func choose(_tgt: Hero, dist: float) -> String:
	var frac := e.life / maxf(e.max_life, 1.0)
	if frac < 0.5 and ready("bb_avalanche"):
		return "bb_avalanche"
	if dist < 5.5 and ready("bb_slam"):
		return "bb_slam"
	if dist < 8.5 and ready("bb_roar"):
		return "bb_roar"
	if dist > 4.0 and dist < 13.0 and ready("bb_lances"):
		return "bb_lances"
	if dist < 3.4 and ready("bb_swing"):
		return "bb_swing"
	return ""

func start(m: String, warn: float) -> void:
	match m:
		"bb_slam":
			cds[m] = 7.0
			e._fx("bb_slam_tele:%.2f" % warn)
		"bb_lances":
			cds[m] = 6.0
			e._fx("bb_lances_tele:%.2f,%.2f,%.2f,%.2f" % [aim_dir.x, aim_dir.z, warn, 12.0])
		"bb_roar":
			cds[m] = 10.0
			e._fx("bb_roar_tele:%.2f,%.2f,%.2f" % [aim_dir.x, aim_dir.z, warn])
		"bb_avalanche":
			cds[m] = 16.0
			marks = []
			for h in heroes_in(e.global_position, 30.0):
				marks.append(h.global_position)
			for k in 6:
				var a := randf() * TAU
				var p := e.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 12.0)
				marks.append(e.game.world.free_spot_near(p, 1.0))
			var txt := ""
			for p in marks:
				txt += "%.1f,%.1f;" % [p.x, p.z]
			e._fx("bb_aval_tele:%.2f:%s" % [warn, txt])
		"bb_swing":
			cds[m] = 1.6

func land(tgt: Hero) -> void:
	var at := e.global_position
	match move:
		"bb_slam":
			e._fx("bb_slam")
			for h in heroes_in(at, 6.0):
				h.take_hit(e._roll() * 1.4, at, "freeze", "cold")
		"bb_lances":
			e._fx("bb_lances:%.2f,%.2f" % [aim_dir.x, aim_dir.z])
			for h in e.game.all_heroes():
				if not is_instance_valid(h) or h.dead:
					continue
				var rel: Vector3 = h.global_position - at
				rel.y = 0
				var along := rel.dot(aim_dir)
				if along > 0.5 and along < 12.5 and (rel - aim_dir * along).length() < 1.4:
					h.take_hit(e._roll() * 1.2, at, "chill", "cold")
		"bb_roar":
			e._fx("bb_roar:%.2f,%.2f" % [aim_dir.x, aim_dir.z])
			for h in heroes_in(at, 9.0):
				var rel: Vector3 = h.global_position - at
				rel.y = 0
				if rel.length() < 0.1 or rel.normalized().dot(aim_dir) > cos(deg_to_rad(35.0)):
					h.take_hit(e._roll() * 0.7, at, "chill", "cold")
		"bb_avalanche":
			e._fx("bb_aval")
			for p in marks:
				for h in heroes_in(p, 2.2):
					h.take_hit(e._roll() * 1.5, p, "quake", "cold")
		"bb_swing":
			if tgt.global_position.distance_to(at) < 3.6:
				tgt.take_hit(e._roll(), at, "sweep", "phys")
