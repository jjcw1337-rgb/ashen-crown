class_name CrushingCoil
extends DragonSkill
## Crushing Coil ("s_coil", a run skill): the serpent whips its body round in a full coil (the tail spin's swing):
## everything round it is crushed and slowed, a chilled foe crushed harder (Iron Coils: further, harder, and life back
## for each foe crushed). On the swing's impact frame its own game makes the "coil" where it stands; the rules (here,
## or on the match server's copy of it) crush. Its look: crushing_coil_fx.gd (CrushingCoilFx: "crush").
## Codex "k": r (metres), dmg (% of the weapon's blow), chilled (% more on a chilled foe), slow (%) and slow_s.

const KNOCK := 1.5
## Iron Coils heals for this many foes at most.
const MOST_HEALS := 5

func cast(_aim: Vector3) -> void:
	hero._start_attack("swipe3", id)

func impact() -> void:
	make("coil", {"p": hero.global_position})

func made(kind: String, d: Dictionary) -> void:
	if kind != "coil":
		return
	var h := hero
	var me: Vector3 = d["p"]
	var r := val("r", 4.2) * (1.0 + h.talent("coil_r") / 100.0)
	var hit: Array = []
	for e in h.game.enemies_near(me, r):
		if not hits(e):
			continue
		var chilled: bool = e.chill_t > 0.0
		h._hit_enemy(e, val("dmg", 130.0) / 100.0 * ((1.0 + val("chilled", 30.0) / 100.0) if chilled else 1.0), KNOCK, id)
		if not e.dead:
			slow(e, val("slow_s", 2.0), val("slow", 45.0) / 100.0)
		hit.append(e)
	if hit.size() > 0 and h.talent("coil_shield") > 0.0:
		h.gain_life(h.max_life * h.talent("coil_shield") / 100.0 * mini(hit.size(), MOST_HEALS))
	h.fx(id, "crush", {"p": me, "r": r, "t": hit})

## Server: a coil where it has the serpent.
func server_ok(kind: String, d: Dictionary) -> bool:
	return kind == "coil" and near_me(d.get("p"), 4.0)
